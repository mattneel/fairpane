//! The OpenType `GSUB` and `GPOS` common tables: ScriptList, Script, LangSys, FeatureList, Feature, LookupList, Lookup,
//! the lookup flags, mark filtering sets, each subtable's format and primary Coverage, and lookup selection by script,
//! language, and feature tags. This file also re-exports Coverage, ClassDef, Device, and `GDEF`.
//! No lookup is applied. Source: the OpenType 1.9.1 `chapter2` (layout common table formats), `gsub`, `gpos`, and `gdef` chapters.
//!
//! Every read goes through `Reader`, offset sums use 64-bit arithmetic, and every count is checked against the remaining
//! bytes before a loop over it starts. No function allocates, takes an allocator, or recurses; extension subtables are
//! followed one level. Each opened structure keeps the counts that it checked, and each accessor reads every index once
//! and checks it at its point of use, so no accessor reads outside the font even when the font bytes change after a check.
//! FeatureVariations, Device, and VariationIndex data, and unknown lookup types and formats, are reported as unsupported.

const std = @import("std");
const builtin = @import("builtin");
const reader = @import("reader.zig");
const tables = @import("tables.zig");
const common = @import("layout_common.zig");
const gdef = @import("gdef.zig");

const Reader = reader.Reader;
const Tag = reader.Tag;
const Defect = tables.Defect;
const TableStatus = tables.TableStatus;

pub const Coverage = common.Coverage;
pub const CoverageIterator = common.CoverageIterator;
pub const ClassDef = common.ClassDef;
pub const DeviceStatus = common.DeviceStatus;
pub const parseCoverage = common.parseCoverage;
pub const parseClassDef = common.parseClassDef;
pub const parseDevice = common.parseDevice;

pub const Gdef = gdef.Gdef;
pub const MarkGlyphSets = gdef.MarkGlyphSets;
pub const LigCaretList = gdef.LigCaretList;
pub const LigGlyph = gdef.LigGlyph;
pub const CaretsStatus = gdef.CaretsStatus;
pub const CaretStatus = gdef.CaretStatus;
pub const CaretValue = gdef.CaretValue;
pub const parseGdef = gdef.parseGdef;

pub const Kind = enum { gsub, gpos };

/// The stored lookup type of an extension lookup: 7 in GSUB and 9 in GPOS.
fn extensionType(kind: Kind) u16 {
    return switch (kind) {
        .gsub => 7,
        .gpos => 9,
    };
}

/// Whether the table kind defines lookup type `lookup_type`: GSUB 1 to 8 and GPOS 1 to 9.
fn definesType(kind: Kind, lookup_type: u16) bool {
    const highest: u16 = switch (kind) {
        .gsub => 8,
        .gpos => 9,
    };
    return lookup_type >= 1 and lookup_type <= highest;
}

/// Whether subtable `format` is defined for the effective `lookup_type`.
fn definesFormat(kind: Kind, lookup_type: u16, format: u16) bool {
    const highest: u16 = switch (kind) {
        .gsub => switch (lookup_type) {
            1 => 2,
            2, 3, 4, 8 => 1,
            5, 6 => 3,
            else => 0,
        },
        .gpos => switch (lookup_type) {
            1, 2 => 2,
            3, 4, 5, 6 => 1,
            7, 8 => 3,
            else => 0,
        },
    };
    return format >= 1 and format <= highest;
}

/// A `GSUB` or `GPOS` table that `parseLayout` checked. The counts come from that check, so a tag read stays inside the
/// record arrays that it checked even when the font bytes change afterward.
pub const Layout = struct {
    table: Reader,
    kind: Kind,
    /// Major version in the high 16 bits and minor version in the low 16 bits.
    version: u32,
    script_list: u16,
    feature_list: u16,
    lookup_list: u16,
    /// The stored FeatureVariations offset; 0 for version 1.0 or a NULL offset. A nonzero offset names variation data
    /// that is not evaluated, so selection reports it and uses the default features.
    feature_variations: u32,
    script_count: u16,
    feature_count: u16,
    lookup_count: u16,

    pub fn scriptCount(self: Layout) u16 {
        return self.script_count;
    }

    /// The tag of script record `i`, or null when `i` is at or past `scriptCount`.
    pub fn scriptTag(self: Layout, i: u16) ?[4]u8 {
        if (i >= self.script_count) return null;
        return self.table.tagAt(@as(u64, self.script_list) + 2 + 6 * @as(u64, i));
    }

    /// The number of features, in FeatureList order.
    pub fn featureCount(self: Layout) u16 {
        return self.feature_count;
    }

    /// The tag of feature record `i`, or null when `i` is at or past `featureCount`.
    pub fn featureTag(self: Layout, i: u16) ?[4]u8 {
        if (i >= self.feature_count) return null;
        return self.table.tagAt(@as(u64, self.feature_list) + 2 + 6 * @as(u64, i));
    }

    pub fn lookupCount(self: Layout) u16 {
        return self.lookup_count;
    }

    /// The Script table of script record `i`, or null when `i` is at or past `scriptCount`. Opening it checks its
    /// LangSysRecords, in time linear in their number.
    pub fn script(self: Layout, i: u16) ?TableStatus(Script) {
        if (i >= self.script_count) return null;
        const record = self.table.fixed(6, @as(u64, self.script_list) + 2 + 6 * @as(u64, i)) orelse return .{ .rejected = .count_out_of_bounds };
        const offset = record.int(u16, 4);
        if (offset == 0) return .{ .rejected = .null_offset };
        return openScript(self.table, @as(u64, self.script_list) + offset, record.array(4, 0), self.feature_count);
    }

    /// The Feature table of feature record `i`, or null when `i` is at or past `featureCount`. Opening it checks its
    /// lookup indices, in time linear in their number.
    pub fn feature(self: Layout, i: u16) ?TableStatus(Feature) {
        if (i >= self.feature_count) return null;
        const record = self.table.fixed(6, @as(u64, self.feature_list) + 2 + 6 * @as(u64, i)) orelse return .{ .rejected = .count_out_of_bounds };
        const offset = record.int(u16, 4);
        if (offset == 0) return .{ .rejected = .null_offset };
        return openFeature(self.table, @as(u64, self.feature_list) + offset, record.array(4, 0), self.lookup_count);
    }

    /// Lookup `i` of the LookupList, or null when `i` is at or past `lookupCount`. Opening it checks its subtable offsets
    /// and, for an extension lookup, each extension header, in time linear in its subtable count.
    pub fn lookup(self: Layout, i: u16) ?LookupStatus {
        if (i >= self.lookup_count) return null;
        const offset = self.table.u16At(@as(u64, self.lookup_list) + 2 + 2 * @as(u64, i)) orelse return .{ .rejected = .count_out_of_bounds };
        if (offset == 0) return .{ .rejected = .null_offset };
        return openLookup(self.table, self.kind, @as(u64, self.lookup_list) + offset);
    }

    /// Selects the lookups of `request` as the `chapter2` "Scripts and languages" and "Feature table" sections specify.
    /// Bit p of `masks[i]` is set when the feature `request.features[p]` uses lookup i, and bit 63 when the required
    /// feature uses it. The caller applies the lookups with nonzero masks in ascending index order, which is LookupList order.
    /// Only `masks[0..lookupCount]` is written. After `rejected` or `limit_exceeded`, its contents are unspecified.
    /// Selection work, one unit for each feature index and each lookup index that it reads, is limited by `limits.max_work`.
    pub fn selectLookups(self: Layout, request: Request, limits: SelectionLimits, masks: []u64) SelectError!SelectionStatus {
        if (request.features.len > 63) return error.TooManyFeatures;
        if (masks.len < self.lookup_count) return error.MasksTooShort;
        @memset(masks[0..self.lookup_count], 0);
        if (builtin.is_test) work = 0;
        var selection: Selection = .{
            .script = null,
            .lang_sys = .none,
            .required_feature = null,
            .lookup_count = 0,
            .feature_variations = self.feature_variations != 0,
        };

        const index = self.findScript(request.script) orelse self.findScript("DFLT".*) orelse return .{ .valid = selection };
        const s = switch (self.script(index) orelse unreachable) { // findScript returns an index below scriptCount.
            .valid => |v| v,
            .rejected => |defect| return .{ .rejected = defect },
            .absent, .unsupported_version => unreachable, // openScript reports neither.
        };
        selection.script = s.tag;

        const lang_sys: LangSys = found: {
            if (request.language) |language| {
                var j: u16 = 0;
                while (j < s.lang_sys_count) : (j += 1) {
                    const tag = s.langSysTag(j) orelse break;
                    if (!std.mem.eql(u8, &tag, &language)) continue;
                    selection.lang_sys = .requested;
                    break :found switch (s.langSys(j) orelse unreachable) { // j is below lang_sys_count.
                        .valid => |v| v,
                        .rejected => |defect| return .{ .rejected = defect },
                        .absent, .unsupported_version => unreachable, // openLangSys reports neither.
                    };
                }
            }
            switch (s.defaultLangSys()) {
                .valid => |v| {
                    selection.lang_sys = .default;
                    break :found v;
                },
                .absent => return .{ .valid = selection },
                .rejected => |defect| return .{ .rejected = defect },
                .unsupported_version => unreachable, // openLangSys never reports it.
            }
        };
        selection.required_feature = lang_sys.required_feature;

        var budget: Budget = .{ .max = limits.max_work };
        if (self.addLangSys(lang_sys, request.features, masks, &budget)) |status| return status;

        for (masks[0..self.lookup_count]) |m| {
            if (m != 0) selection.lookup_count += 1;
        }
        return .{ .valid = selection };
    }

    /// The first script record with `tag`, by a linear scan of the checked records.
    fn findScript(self: Layout, tag: Tag) ?u16 {
        var i: u16 = 0;
        while (i < self.script_count) : (i += 1) {
            const record = self.scriptTag(i) orelse return null;
            if (std.mem.eql(u8, &record, &tag)) return i;
        }
        return null;
    }

    /// Steps 7 and 8 of selection for one LangSys: ORs the request bits of each listed feature that the request names, and
    /// bit 63 and the request bits of the required feature, into the masks of their lookups.
    /// Returns a status only when selection stops.
    fn addLangSys(self: Layout, lang_sys: LangSys, features: []const Tag, masks: []u64, budget: *Budget) ?SelectionStatus {
        var k: u16 = 0;
        while (k < lang_sys.feature_index_count) : (k += 1) {
            if (!budget.charge()) return .limit_exceeded;
            const f = self.table.u16At(lang_sys.offset + 6 + 2 * @as(u64, k)) orelse return .{ .rejected = .count_out_of_bounds };
            if (f >= self.feature_count) return .{ .rejected = .index_out_of_range };
            const tag = self.featureTag(f) orelse return .{ .rejected = .count_out_of_bounds };
            const bits = requestBits(features, tag);
            if (bits == 0) continue;
            if (self.addFeature(f, bits, masks, budget)) |status| return status;
        }
        if (lang_sys.required_feature) |r| {
            if (r >= self.feature_count) return .{ .rejected = .index_out_of_range };
            const tag = self.featureTag(r) orelse return .{ .rejected = .count_out_of_bounds };
            if (self.addFeature(r, required_bit | requestBits(features, tag), masks, budget)) |status| return status;
        }
        return null;
    }

    /// ORs `bits` into the mask of every lookup that Feature `f` lists. Returns a status only when selection stops.
    fn addFeature(self: Layout, f: u16, bits: u64, masks: []u64, budget: *Budget) ?SelectionStatus {
        const opened = switch (self.feature(f) orelse unreachable) { // f is below featureCount.
            .valid => |v| v,
            .rejected => |defect| return .{ .rejected = defect },
            .absent, .unsupported_version => unreachable, // openFeature reports neither.
        };
        var k: u16 = 0;
        while (k < opened.lookup_index_count) : (k += 1) {
            if (!budget.charge()) return .limit_exceeded;
            const i = self.table.u16At(opened.offset + 4 + 2 * @as(u64, k)) orelse return .{ .rejected = .count_out_of_bounds };
            if (i >= self.lookup_count) return .{ .rejected = .index_out_of_range };
            masks[i] |= bits;
        }
        return null;
    }
};

const required_bit: u64 = 1 << 63;

/// The bits p for which `features[p]` equals `tag`.
fn requestBits(features: []const Tag, tag: Tag) u64 {
    var bits: u64 = 0;
    for (features, 0..) |requested, p| {
        if (std.mem.eql(u8, &requested, &tag)) bits |= @as(u64, 1) << @intCast(p);
    }
    return bits;
}

/// Counts selection work against the caller's limit.
const Budget = struct {
    used: u32 = 0,
    max: u32,

    /// Charges one unit before a counted read, or returns false when the limit is already reached.
    fn charge(self: *Budget) bool {
        if (self.used == self.max) return false;
        self.used += 1;
        if (builtin.is_test) work = self.used;
        return true;
    }
};

/// Selection work in test builds: one for each featureIndices and lookupListIndices entry that steps 7 and 8 of "Selection" read.
/// Validation inside an opening call is not counted. Each selectLookups call resets it.
/// Concurrent selections in a test build race on this counter.
pub var work: if (builtin.is_test) u32 else void = if (builtin.is_test) 0 else {};

pub const Request = struct {
    script: Tag,
    language: ?Tag = null,
    /// At most 63 tags. A caller with more tags splits the request across calls and combines the masks.
    features: []const Tag,
};

pub const SelectionLimits = struct { max_work: u32 = 1 << 20 };

pub const Selection = struct {
    /// The script record used: the requested tag, `DFLT`, or null when neither exists.
    script: ?Tag,
    lang_sys: enum { requested, default, none },
    required_feature: ?u16,
    /// The number of nonzero masks.
    lookup_count: u16,
    /// Whether the table has a FeatureVariations table, which is not evaluated. The masks then hold the default features.
    feature_variations: bool,
};

pub const SelectionStatus = union(enum) { rejected: Defect, limit_exceeded, valid: Selection };

pub const SelectError = error{ TooManyFeatures, MasksTooShort };

/// A Script table whose LangSysRecords `Layout.script` checked.
pub const Script = struct {
    tag: Tag,
    lang_sys_count: u16,
    table: Reader,
    offset: u64,
    default_lang_sys: u16,
    feature_count: u16,

    /// The default LangSys table, or `.absent` for a NULL offset.
    pub fn defaultLangSys(self: Script) TableStatus(LangSys) {
        if (self.default_lang_sys == 0) return .absent;
        return openLangSys(self.table, self.offset + self.default_lang_sys, self.feature_count);
    }

    /// The tag of LangSysRecord `j`, or null when `j` is at or past `lang_sys_count`.
    pub fn langSysTag(self: Script, j: u16) ?Tag {
        if (j >= self.lang_sys_count) return null;
        return self.table.tagAt(self.offset + 4 + 6 * @as(u64, j));
    }

    /// The LangSys table of LangSysRecord `j`, or null when `j` is at or past `lang_sys_count`.
    pub fn langSys(self: Script, j: u16) ?TableStatus(LangSys) {
        if (j >= self.lang_sys_count) return null;
        const offset = self.table.u16At(self.offset + 4 + 6 * @as(u64, j) + 4) orelse return .{ .rejected = .count_out_of_bounds };
        if (offset == 0) return .{ .rejected = .null_offset };
        return openLangSys(self.table, self.offset + offset, self.feature_count);
    }
};

fn openScript(t: Reader, at: u64, tag: Tag, feature_count: u16) TableStatus(Script) {
    if (at >= t.len()) return .{ .rejected = .offset_out_of_bounds };
    const header = t.fixed(4, at) orelse return .{ .rejected = .too_short };
    const default_offset = header.int(u16, 0);
    const count = header.int(u16, 2);
    if (!t.fits(at + 4, 6 * @as(u64, count))) return .{ .rejected = .count_out_of_bounds };
    var previous: Tag = undefined;
    var j: u64 = 0;
    while (j < count) : (j += 1) {
        const lang = t.tagAt(at + 4 + 6 * j) orelse return .{ .rejected = .count_out_of_bounds };
        if (j > 0 and std.mem.order(u8, &previous, &lang) != .lt) return .{ .rejected = .unsorted_records };
        previous = lang;
    }
    if (default_offset != 0 and at + default_offset >= t.len()) return .{ .rejected = .offset_out_of_bounds };
    j = 0;
    while (j < count) : (j += 1) {
        const offset = t.u16At(at + 4 + 6 * j + 4) orelse return .{ .rejected = .count_out_of_bounds };
        if (offset == 0) return .{ .rejected = .null_offset };
        if (at + offset >= t.len()) return .{ .rejected = .offset_out_of_bounds };
    }
    if (std.mem.eql(u8, &tag, "DFLT") and default_offset == 0) return .{ .rejected = .missing_default_lang_sys };
    return .{ .valid = .{
        .tag = tag,
        .lang_sys_count = count,
        .table = t,
        .offset = at,
        .default_lang_sys = default_offset,
        .feature_count = feature_count,
    } };
}

/// A LangSys table whose feature indices were checked against featureCount. lookupOrderOffset is ignored.
pub const LangSys = struct {
    /// Null for 0xFFFF.
    required_feature: ?u16,
    feature_index_count: u16,
    table: Reader,
    offset: u64,
    feature_count: u16,

    /// Feature index `k`, or null when `k` is at or past `feature_index_count` or when the stored index is no longer
    /// below featureCount because the font bytes changed after the check.
    pub fn featureIndex(self: LangSys, k: u16) ?u16 {
        if (k >= self.feature_index_count) return null;
        const f = self.table.u16At(self.offset + 6 + 2 * @as(u64, k)) orelse return null;
        return if (f < self.feature_count) f else null;
    }
};

fn openLangSys(t: Reader, at: u64, feature_count: u16) TableStatus(LangSys) {
    if (at >= t.len()) return .{ .rejected = .offset_out_of_bounds };
    const header = t.fixed(6, at) orelse return .{ .rejected = .too_short };
    const required = header.int(u16, 2);
    const count = header.int(u16, 4);
    if (!t.fits(at + 6, 2 * @as(u64, count))) return .{ .rejected = .count_out_of_bounds };
    if (required != 0xFFFF and required >= feature_count) return .{ .rejected = .index_out_of_range };
    var k: u64 = 0;
    while (k < count) : (k += 1) {
        const f = t.u16At(at + 6 + 2 * k) orelse return .{ .rejected = .count_out_of_bounds };
        if (f >= feature_count) return .{ .rejected = .index_out_of_range };
    }
    return .{ .valid = .{
        .required_feature = if (required == 0xFFFF) null else required,
        .feature_index_count = count,
        .table = t,
        .offset = at,
        .feature_count = feature_count,
    } };
}

/// A Feature table whose lookup indices were checked against lookupCount.
pub const Feature = struct {
    tag: Tag,
    /// The stored featureParamsOffset; FeatureParams are never read.
    params_offset: u16,
    lookup_index_count: u16,
    table: Reader,
    offset: u64,
    lookup_count: u16,

    /// Lookup index `k`, or null when `k` is at or past `lookup_index_count` or when the stored index is no longer below
    /// lookupCount because the font bytes changed after the check.
    pub fn lookupIndex(self: Feature, k: u16) ?u16 {
        if (k >= self.lookup_index_count) return null;
        const i = self.table.u16At(self.offset + 4 + 2 * @as(u64, k)) orelse return null;
        return if (i < self.lookup_count) i else null;
    }
};

fn openFeature(t: Reader, at: u64, tag: Tag, lookup_count: u16) TableStatus(Feature) {
    if (at >= t.len()) return .{ .rejected = .offset_out_of_bounds };
    const header = t.fixed(4, at) orelse return .{ .rejected = .too_short };
    const count = header.int(u16, 2);
    if (!t.fits(at + 4, 2 * @as(u64, count))) return .{ .rejected = .count_out_of_bounds };
    var k: u64 = 0;
    while (k < count) : (k += 1) {
        const i = t.u16At(at + 4 + 2 * k) orelse return .{ .rejected = .count_out_of_bounds };
        if (i >= lookup_count) return .{ .rejected = .index_out_of_range };
    }
    return .{ .valid = .{
        .tag = tag,
        .params_offset = header.int(u16, 0),
        .lookup_index_count = count,
        .table = t,
        .offset = at,
        .lookup_count = lookup_count,
    } };
}

const right_to_left: u16 = 0x0001;
const ignore_base_glyphs: u16 = 0x0002;
const ignore_ligatures: u16 = 0x0004;
const ignore_marks: u16 = 0x0008;
const use_mark_filtering_set: u16 = 0x0010;

pub const LookupStatus = union(enum) {
    rejected: Defect,
    /// A stored type, or an extension's type, that the table kind does not define.
    unsupported_type: u16,
    unsupported_extension_format: u16,
    valid: Lookup,
};

/// A Lookup table whose subtable offsets, and for an extension lookup whose extension headers, were checked.
pub const Lookup = struct {
    /// The effective type: extensionLookupType for an extension lookup with subtables.
    lookup_type: u16,
    /// Whether the stored type is 7 (GSUB) or 9 (GPOS). An extension lookup with no subtables keeps that stored type.
    extension: bool,
    /// As stored, including the reserved bits 0x00E0.
    flag: u16,
    subtable_count: u16,
    mark_filtering_set: ?u16,
    table: Reader,
    kind: Kind,
    offset: u64,

    pub fn rightToLeft(self: Lookup) bool {
        return self.flag & right_to_left != 0;
    }
    pub fn ignoreBaseGlyphs(self: Lookup) bool {
        return self.flag & ignore_base_glyphs != 0;
    }
    pub fn ignoreLigatures(self: Lookup) bool {
        return self.flag & ignore_ligatures != 0;
    }
    pub fn ignoreMarks(self: Lookup) bool {
        return self.flag & ignore_marks != 0;
    }
    pub fn useMarkFilteringSet(self: Lookup) bool {
        return self.flag & use_mark_filtering_set != 0;
    }
    /// The mark attachment class filter in the high byte of the flag.
    pub fn markAttachmentClass(self: Lookup) u8 {
        return @intCast(self.flag >> 8);
    }

    /// Subtable `k`, or null when `k` is at or past `subtable_count`. For an extension lookup, this is the extension's
    /// target, of the type that the opening check found.
    pub fn subtable(self: Lookup, k: u16) ?SubtableStatus {
        if (k >= self.subtable_count) return null;
        const t = self.table;
        const offset = t.u16At(self.offset + 6 + 2 * @as(u64, k)) orelse return .{ .rejected = .count_out_of_bounds };
        if (offset == 0) return .{ .rejected = .null_offset };
        var at = self.offset + offset;
        if (at >= t.len()) return .{ .rejected = .offset_out_of_bounds };
        if (self.extension) {
            const header = t.fixed(8, at) orelse return .{ .rejected = .too_short };
            at += header.int(u32, 4);
            if (at >= t.len()) return .{ .rejected = .offset_out_of_bounds };
        }
        const format = t.u16At(at) orelse return .{ .rejected = .too_short };
        if (!definesFormat(self.kind, self.lookup_type, format)) return .{ .unsupported_format = format };
        return .{ .valid = .{ .format = format, .table = t, .kind = self.kind, .lookup_type = self.lookup_type, .offset = at } };
    }
};

fn openLookup(t: Reader, kind: Kind, at: u64) LookupStatus {
    if (at >= t.len()) return .{ .rejected = .offset_out_of_bounds };
    const header = t.fixed(6, at) orelse return .{ .rejected = .too_short };
    const stored = header.int(u16, 0);
    const flag = header.int(u16, 2);
    const count = header.int(u16, 4);
    if (!t.fits(at + 6, 2 * @as(u64, count))) return .{ .rejected = .count_out_of_bounds };
    var mark_filtering_set: ?u16 = null;
    if (flag & use_mark_filtering_set != 0) {
        mark_filtering_set = t.u16At(at + 6 + 2 * @as(u64, count)) orelse return .{ .rejected = .too_short };
    }
    var k: u64 = 0;
    while (k < count) : (k += 1) {
        const offset = t.u16At(at + 6 + 2 * k) orelse return .{ .rejected = .count_out_of_bounds };
        if (offset == 0) return .{ .rejected = .null_offset };
        if (at + offset >= t.len()) return .{ .rejected = .offset_out_of_bounds };
    }
    if (!definesType(kind, stored)) return .{ .unsupported_type = stored };
    const extension = stored == extensionType(kind);
    var lookup_type = stored;
    if (extension) {
        k = 0;
        while (k < count) : (k += 1) {
            const sub = at + (t.u16At(at + 6 + 2 * k) orelse return .{ .rejected = .count_out_of_bounds });
            const ext = t.fixed(8, sub) orelse return .{ .rejected = .too_short };
            const format = ext.int(u16, 0);
            if (format != 1) return .{ .unsupported_extension_format = format };
            const target_type = ext.int(u16, 2);
            if (target_type == extensionType(kind)) return .{ .rejected = .nested_extension };
            if (!definesType(kind, target_type)) return .{ .unsupported_type = target_type };
            if (k > 0 and target_type != lookup_type) return .{ .rejected = .mixed_lookup_types };
            lookup_type = target_type;
            if (sub + ext.int(u32, 4) >= t.len()) return .{ .rejected = .offset_out_of_bounds };
        }
    }
    return .{ .valid = .{
        .lookup_type = lookup_type,
        .extension = extension,
        .flag = flag,
        .subtable_count = count,
        .mark_filtering_set = mark_filtering_set,
        .table = t,
        .kind = kind,
        .offset = at,
    } };
}

pub const SubtableStatus = union(enum) { rejected: Defect, unsupported_format: u16, valid: Subtable };

/// A lookup subtable of a defined type and format. Its body is not parsed.
pub const Subtable = struct {
    format: u16,
    table: Reader,
    kind: Kind,
    lookup_type: u16,
    offset: u64,

    /// The subtable's first Coverage table, which `chapter2` calls its Coverage table. For SequenceContextFormat3 and
    /// ChainedSequenceContextFormat3, it is the first input coverage, which needs at least one input glyph. For GPOS types
    /// 4, 5, and 6, it is the mark coverage.
    pub fn coverage(self: Subtable) TableStatus(Coverage) {
        const t = self.table;
        var field: u64 = 2;
        if (self.format == 3 and self.lookup_type == contextType(self.kind)) {
            const glyph_count = t.u16At(self.offset + 2) orelse return .{ .rejected = .too_short };
            if (glyph_count == 0) return .{ .rejected = .count_out_of_bounds };
            field = 6;
        } else if (self.format == 3 and self.lookup_type == contextType(self.kind) + 1) {
            const backtrack: u64 = t.u16At(self.offset + 2) orelse return .{ .rejected = .too_short };
            const input = t.u16At(self.offset + 4 + 2 * backtrack) orelse return .{ .rejected = .too_short };
            if (input == 0) return .{ .rejected = .count_out_of_bounds };
            field = 6 + 2 * backtrack;
        }
        const offset = t.u16At(self.offset + field) orelse return .{ .rejected = .too_short };
        if (offset == 0) return .{ .rejected = .null_offset };
        return common.parseCoverage(t, self.offset + offset);
    }
};

/// The contextual lookup type: GSUB 5 and GPOS 7. The chained contextual type follows it.
fn contextType(kind: Kind) u16 {
    return switch (kind) {
        .gsub => 5,
        .gpos => 7,
    };
}

const List = union(enum) { count: u16, rejected: Defect };

/// Checks a list of `count` records of `record_size` bytes that starts at `list`, and that each record's 16-bit offset,
/// at `offset_at` inside the record and relative to the list, falls inside the table. A null list has no records.
fn checkList(t: Reader, list: u16, record_size: u64, offset_at: u64, comptime sorted_tags: bool) List {
    if (list == 0) return .{ .count = 0 };
    const count = t.u16At(list) orelse return .{ .rejected = .offset_out_of_bounds };
    if (!t.fits(@as(u64, list) + 2, record_size * count)) return .{ .rejected = .count_out_of_bounds };
    var previous: [4]u8 = undefined;
    var i: u64 = 0;
    while (i < count) : (i += 1) {
        const record = @as(u64, list) + 2 + record_size * i;
        if (sorted_tags) {
            const tag = t.tagAt(record) orelse return .{ .rejected = .count_out_of_bounds };
            if (i > 0 and std.mem.order(u8, &previous, &tag) != .lt) return .{ .rejected = .unsorted_records };
            previous = tag;
        }
        const offset = t.u16At(record + offset_at) orelse return .{ .rejected = .count_out_of_bounds };
        if (@as(u64, list) + offset >= t.len()) return .{ .rejected = .offset_out_of_bounds };
    }
    return .{ .count = count };
}

/// Versions 1.0 and 1.1 with every list offset, record array, and Script, Feature, and Lookup offset inside the table,
/// checked in time linear in the table length.
pub fn parseLayout(t: Reader, kind: Kind) TableStatus(Layout) {
    const major = t.u16At(0) orelse return .{ .rejected = .too_short };
    const minor = t.u16At(2) orelse return .{ .rejected = .too_short };
    const version = (@as(u32, major) << 16) | minor;
    if (major != 1 or minor > 1) return .{ .unsupported_version = version };
    if (t.len() < @as(u64, if (minor == 1) 14 else 10)) return .{ .rejected = .too_short };
    const header = t.fixed(10, 0) orelse return .{ .rejected = .too_short };
    const lists = [3]u16{ header.int(u16, 4), header.int(u16, 6), header.int(u16, 8) };
    // A nonnull list offset must leave room for the list's count.
    for (lists) |list| {
        if (list != 0 and !t.fits(list, 2)) return .{ .rejected = .offset_out_of_bounds };
    }
    var variations: u32 = 0;
    if (minor == 1) {
        variations = t.u32At(10) orelse return .{ .rejected = .too_short };
        if (variations != 0 and variations >= t.len()) return .{ .rejected = .offset_out_of_bounds };
    }
    const scripts = switch (checkList(t, lists[0], 6, 4, true)) {
        .count => |n| n,
        .rejected => |defect| return .{ .rejected = defect },
    };
    const features = switch (checkList(t, lists[1], 6, 4, false)) {
        .count => |n| n,
        .rejected => |defect| return .{ .rejected = defect },
    };
    const lookups = switch (checkList(t, lists[2], 2, 0, false)) {
        .count => |n| n,
        .rejected => |defect| return .{ .rejected = defect },
    };
    return .{ .valid = .{
        .table = t,
        .kind = kind,
        .version = version,
        .script_list = lists[0],
        .feature_list = lists[1],
        .lookup_list = lists[2],
        .feature_variations = variations,
        .script_count = scripts,
        .feature_count = features,
        .lookup_count = lookups,
    } };
}
