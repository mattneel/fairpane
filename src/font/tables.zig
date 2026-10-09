//! The OpenType `head`, `hhea`, `maxp`, `hmtx`, `loca`, `glyf` header, `name`, `OS/2`, and `post` tables.
//! Required tables fail the font with an error; optional tables return a `TableStatus` and never fail the font.

const std = @import("std");
const reader_mod = @import("reader.zig");
const Reader = reader_mod.Reader;

pub const Outline = enum { truetype, cff };

/// Why an optional table was rejected.
pub const Defect = enum {
    too_short,
    offset_out_of_bounds,
    count_out_of_bounds,
    unsorted_records,
    glyph_count_mismatch,
    invalid_string_index,
    odd_utf16_length,
};

/// The result of reading an optional table.
pub fn TableStatus(comptime T: type) type {
    return union(enum) {
        absent,
        rejected: Defect,
        /// The table's version or format, as stored.
        unsupported_version: u32,
        valid: T,
    };
}

pub const Head = struct {
    major_version: u16,
    minor_version: u16,
    /// A 16.16 fixed-point value, as stored.
    font_revision: i32,
    checksum_adjustment: u32,
    magic_number: u32,
    flags: u16,
    units_per_em: u16,
    created: i64,
    modified: i64,
    x_min: i16,
    y_min: i16,
    x_max: i16,
    y_max: i16,
    mac_style: u16,
    lowest_rec_ppem: u16,
    font_direction_hint: i16,
    index_to_loc_format: i16,
    glyph_data_format: i16,
};

/// Length at least 54, major version 1, the magic number, unitsPerEm from 16 to 16384, and for TrueType a loca format of 0 or 1.
pub fn parseHead(r: Reader, outline: Outline) error{InvalidHead}!Head {
    const h = r.fixed(54, 0) orelse return error.InvalidHead;
    const head: Head = .{
        .major_version = h.int(u16, 0),
        .minor_version = h.int(u16, 2),
        .font_revision = h.int(i32, 4),
        .checksum_adjustment = h.int(u32, 8),
        .magic_number = h.int(u32, 12),
        .flags = h.int(u16, 16),
        .units_per_em = h.int(u16, 18),
        .created = h.int(i64, 20),
        .modified = h.int(i64, 28),
        .x_min = h.int(i16, 36),
        .y_min = h.int(i16, 38),
        .x_max = h.int(i16, 40),
        .y_max = h.int(i16, 42),
        .mac_style = h.int(u16, 44),
        .lowest_rec_ppem = h.int(u16, 46),
        .font_direction_hint = h.int(i16, 48),
        .index_to_loc_format = h.int(i16, 50),
        .glyph_data_format = h.int(i16, 52),
    };
    if (head.major_version != 1 or head.magic_number != 0x5F0F3CF5) return error.InvalidHead;
    if (head.units_per_em < 16 or head.units_per_em > 16384) return error.InvalidHead;
    if (outline == .truetype and head.index_to_loc_format != 0 and head.index_to_loc_format != 1) return error.InvalidHead;
    return head;
}

pub const MaxpV1 = struct {
    max_points: u16,
    max_contours: u16,
    max_composite_points: u16,
    max_composite_contours: u16,
    max_zones: u16,
    max_twilight_points: u16,
    max_storage: u16,
    max_function_defs: u16,
    max_instruction_defs: u16,
    max_stack_elements: u16,
    max_size_of_instructions: u16,
    max_component_elements: u16,
    max_component_depth: u16,
};

pub const Maxp = struct {
    version: u32,
    num_glyphs: u16,
    /// The version 1.0 fields; null for version 0.5.
    v1: ?MaxpV1,
};

/// TrueType needs version 1.0 and 32 bytes; CFF needs version 0.5 and 6 bytes; numGlyphs is at least 1.
pub fn parseMaxp(r: Reader, outline: Outline) error{InvalidMaxp}!Maxp {
    const version = r.u32At(0) orelse return error.InvalidMaxp;
    const num_glyphs = r.u16At(4) orelse return error.InvalidMaxp;
    if (num_glyphs == 0) return error.InvalidMaxp;
    switch (outline) {
        .cff => {
            if (version != 0x00005000) return error.InvalidMaxp;
            return .{ .version = version, .num_glyphs = num_glyphs, .v1 = null };
        },
        .truetype => {
            if (version != 0x00010000) return error.InvalidMaxp;
            const m = r.fixed(32, 0) orelse return error.InvalidMaxp;
            return .{ .version = version, .num_glyphs = num_glyphs, .v1 = .{
                .max_points = m.int(u16, 6),
                .max_contours = m.int(u16, 8),
                .max_composite_points = m.int(u16, 10),
                .max_composite_contours = m.int(u16, 12),
                .max_zones = m.int(u16, 14),
                .max_twilight_points = m.int(u16, 16),
                .max_storage = m.int(u16, 18),
                .max_function_defs = m.int(u16, 20),
                .max_instruction_defs = m.int(u16, 22),
                .max_stack_elements = m.int(u16, 24),
                .max_size_of_instructions = m.int(u16, 26),
                .max_component_elements = m.int(u16, 28),
                .max_component_depth = m.int(u16, 30),
            } };
        },
    }
}

pub const Hhea = struct {
    major_version: u16,
    minor_version: u16,
    ascender: i16,
    descender: i16,
    line_gap: i16,
    advance_width_max: u16,
    min_left_side_bearing: i16,
    min_right_side_bearing: i16,
    x_max_extent: i16,
    caret_slope_rise: i16,
    caret_slope_run: i16,
    caret_offset: i16,
    metric_data_format: i16,
    number_of_h_metrics: u16,
};

/// Length at least 36, major version 1, and numberOfHMetrics from 1 to numGlyphs.
pub fn parseHhea(r: Reader, num_glyphs: u16) error{InvalidHhea}!Hhea {
    const h = r.fixed(36, 0) orelse return error.InvalidHhea;
    const hhea: Hhea = .{
        .major_version = h.int(u16, 0),
        .minor_version = h.int(u16, 2),
        .ascender = h.int(i16, 4),
        .descender = h.int(i16, 6),
        .line_gap = h.int(i16, 8),
        .advance_width_max = h.int(u16, 10),
        .min_left_side_bearing = h.int(i16, 12),
        .min_right_side_bearing = h.int(i16, 14),
        .x_max_extent = h.int(i16, 16),
        .caret_slope_rise = h.int(i16, 18),
        .caret_slope_run = h.int(i16, 20),
        .caret_offset = h.int(i16, 22),
        .metric_data_format = h.int(i16, 32),
        .number_of_h_metrics = h.int(u16, 34),
    };
    if (hhea.major_version != 1) return error.InvalidHhea;
    if (hhea.number_of_h_metrics == 0 or hhea.number_of_h_metrics > num_glyphs) return error.InvalidHhea;
    return hhea;
}

pub const HMetric = struct { advance: u16, lsb: i16 };

/// The `hmtx` length must hold numberOfHMetrics long metrics and one left side bearing for each remaining glyph.
pub fn checkHmtx(r: Reader, number_of_h_metrics: u16, num_glyphs: u16) error{InvalidHmtx}!void {
    if (number_of_h_metrics > num_glyphs) return error.InvalidHmtx;
    const needed = 4 * @as(u64, number_of_h_metrics) + 2 * @as(u64, num_glyphs - number_of_h_metrics);
    if (r.len() < needed) return error.InvalidHmtx;
}

/// The horizontal metric of `glyph`, or null when the `hmtx` table does not hold it, which `checkHmtx` rules out
/// for every glyph below numGlyphs.
pub fn hmetric(r: Reader, number_of_h_metrics: u16, glyph: u16) ?HMetric {
    if (number_of_h_metrics == 0) return null;
    if (glyph < number_of_h_metrics) {
        const m = r.fixed(4, 4 * @as(u64, glyph)) orelse return null;
        return .{ .advance = m.int(u16, 0), .lsb = m.int(i16, 2) };
    }
    return .{
        .advance = r.u16At(4 * @as(u64, number_of_h_metrics - 1)) orelse return null,
        .lsb = r.i16At(4 * @as(u64, number_of_h_metrics) + 2 * @as(u64, glyph - number_of_h_metrics)) orelse return null,
    };
}

pub const Loca = struct {
    table: Reader,
    long: bool,

    /// The byte offset of glyph entry `i` inside `glyf`, or null when the entry lies outside `loca`. Short entries are doubled.
    pub fn offset(self: Loca, i: u64) ?u64 {
        if (self.long) return @as(u64, self.table.u32At(4 * i) orelse return null);
        return 2 * @as(u64, self.table.u16At(2 * i) orelse return null);
    }
};

/// numGlyphs + 1 entries must fit, offsets never decrease, and the last offset is at most the glyf length.
pub fn parseLoca(r: Reader, index_to_loc_format: i16, num_glyphs: u16, glyf_len: u64) error{InvalidLoca}!Loca {
    const loca: Loca = .{ .table = r, .long = index_to_loc_format == 1 };
    const entries = @as(u64, num_glyphs) + 1;
    if (r.len() < entries * @as(u64, if (loca.long) 4 else 2)) return error.InvalidLoca;
    var previous: u64 = 0;
    var i: u64 = 0;
    while (i < entries) : (i += 1) {
        const o = loca.offset(i) orelse return error.InvalidLoca;
        if (o < previous) return error.InvalidLoca;
        previous = o;
    }
    if (previous > glyf_len) return error.InvalidLoca;
    return loca;
}

pub const GlyphHeader = struct {
    number_of_contours: i16,
    x_min: i16,
    y_min: i16,
    x_max: i16,
    y_max: i16,
};

/// Checks one glyph's header. Outline points, flags, and composite components are not decoded.
pub fn glyphHeader(glyph: Reader) error{InvalidGlyph}!?GlyphHeader {
    if (glyph.len() == 0) return null;
    const h = glyph.fixed(10, 0) orelse return error.InvalidGlyph;
    const header: GlyphHeader = .{
        .number_of_contours = h.int(i16, 0),
        .x_min = h.int(i16, 2),
        .y_min = h.int(i16, 4),
        .x_max = h.int(i16, 6),
        .y_max = h.int(i16, 8),
    };
    if (header.number_of_contours >= 0) {
        const contours: u64 = @intCast(header.number_of_contours);
        const instruction_at = 10 + 2 * contours;
        const instruction_length = glyph.u16At(instruction_at) orelse return error.InvalidGlyph;
        var previous: u16 = 0;
        var i: u64 = 0;
        while (i < contours) : (i += 1) {
            const end = glyph.u16At(10 + 2 * i) orelse return error.InvalidGlyph;
            if (i > 0 and end < previous) return error.InvalidGlyph;
            previous = end;
        }
        if (!glyph.fits(instruction_at + 2, instruction_length)) return error.InvalidGlyph;
    }
    return header;
}

pub const NameRecord = struct {
    platform_id: u16,
    encoding_id: u16,
    language_id: u16,
    name_id: u16,
    /// The raw string bytes, without decoding.
    bytes: []const u8,
};

/// A `name` table that `parseName` checked. `count` and the storage offset come from that check.
/// The records and strings are read again on each call.
pub const Name = struct {
    table: Reader,
    format: u16,
    record_count: u16,
    storage: u16,

    pub fn count(self: Name) u16 {
        return self.record_count;
    }

    /// Record `i`, or null when `i` is at or past `count`, or when its string no longer lies inside the table
    /// because the font bytes changed after the check.
    pub fn record(self: Name, i: u16) ?NameRecord {
        if (i >= self.record_count) return null;
        const r = self.table.fixed(12, 6 + 12 * @as(u64, i)) orelse return null;
        return .{
            .platform_id = r.int(u16, 0),
            .encoding_id = r.int(u16, 2),
            .language_id = r.int(u16, 4),
            .name_id = r.int(u16, 6),
            .bytes = self.table.slice(@as(u64, self.storage) + r.int(u16, 10), r.int(u16, 8)) orelse return null,
        };
    }

    /// The raw string of the first readable record with these identifiers.
    pub fn find(self: Name, platform_id: u16, encoding_id: u16, language_id: u16, name_id: u16) ?[]const u8 {
        var i: u16 = 0;
        while (i < self.record_count) : (i += 1) {
            const r = self.record(i) orelse continue;
            if (r.platform_id == platform_id and r.encoding_id == encoding_id and r.language_id == language_id and r.name_id == name_id) return r.bytes;
        }
        return null;
    }
};

/// Checks the `name` table in time linear in its length.
pub fn parseName(r: Reader) TableStatus(Name) {
    const format = r.u16At(0) orelse return .{ .rejected = .too_short };
    if (format > 1) return .{ .unsupported_version = format };
    const header = r.fixed(6, 0) orelse return .{ .rejected = .too_short };
    const count = header.int(u16, 2);
    const storage = header.int(u16, 4);
    const records_end = 6 + 12 * @as(u64, count);
    if (!r.fits(0, records_end)) return .{ .rejected = .count_out_of_bounds };
    var lang_tags: u64 = 0;
    if (format == 1) {
        lang_tags = r.u16At(records_end) orelse return .{ .rejected = .count_out_of_bounds };
        if (!r.fits(records_end + 2, 4 * lang_tags)) return .{ .rejected = .count_out_of_bounds };
    }
    if (storage > r.len()) return .{ .rejected = .offset_out_of_bounds };
    var previous: u64 = 0;
    var i: u64 = 0;
    while (i < count) : (i += 1) {
        const record = r.fixed(12, 6 + 12 * i) orelse return .{ .rejected = .count_out_of_bounds };
        const platform = record.int(u16, 0);
        const length = record.int(u16, 8);
        if (!r.fits(@as(u64, storage) + record.int(u16, 10), length)) return .{ .rejected = .offset_out_of_bounds };
        const key = std.mem.readInt(u64, record.bytes[0..8], .big);
        if (i > 0 and key < previous) return .{ .rejected = .unsorted_records };
        previous = key;
        if ((platform == 0 or platform == 3) and length % 2 != 0) return .{ .rejected = .odd_utf16_length };
    }
    i = 0;
    while (i < lang_tags) : (i += 1) {
        const tag = r.fixed(4, records_end + 2 + 4 * i) orelse return .{ .rejected = .count_out_of_bounds };
        if (!r.fits(@as(u64, storage) + tag.int(u16, 2), tag.int(u16, 0))) return .{ .rejected = .offset_out_of_bounds };
    }
    return .{ .valid = .{ .table = r, .format = format, .record_count = count, .storage = storage } };
}

pub const Os2Typo = struct {
    s_typo_ascender: i16,
    s_typo_descender: i16,
    s_typo_line_gap: i16,
    us_win_ascent: u16,
    us_win_descent: u16,
};

pub const Os2V1 = struct { ul_code_page_range1: u32, ul_code_page_range2: u32 };

pub const Os2V2 = struct {
    sx_height: i16,
    s_cap_height: i16,
    us_default_char: u16,
    us_break_char: u16,
    us_max_context: u16,
};

pub const Os2V5 = struct { us_lower_optical_point_size: u16, us_upper_optical_point_size: u16 };

pub const Os2 = struct {
    version: u16,
    x_avg_char_width: i16,
    us_weight_class: u16,
    us_width_class: u16,
    fs_type: u16,
    y_subscript_x_size: i16,
    y_subscript_y_size: i16,
    y_subscript_x_offset: i16,
    y_subscript_y_offset: i16,
    y_superscript_x_size: i16,
    y_superscript_y_size: i16,
    y_superscript_x_offset: i16,
    y_superscript_y_offset: i16,
    y_strikeout_size: i16,
    y_strikeout_position: i16,
    s_family_class: i16,
    panose: [10]u8,
    ul_unicode_range1: u32,
    ul_unicode_range2: u32,
    ul_unicode_range3: u32,
    ul_unicode_range4: u32,
    ach_vend_id: [4]u8,
    fs_selection: u16,
    us_first_char_index: u16,
    us_last_char_index: u16,
    /// Null for a legacy version 0 table that ends at usLastCharIndex.
    typo: ?Os2Typo,
    v1: ?Os2V1,
    v2: ?Os2V2,
    v5: ?Os2V5,
};

/// Versions 0 to 5, with minimum lengths 68, 86, 96, 96, 96, and 100.
pub fn parseOs2(r: Reader) TableStatus(Os2) {
    const version = r.u16At(0) orelse return .{ .rejected = .too_short };
    if (version > 5) return .{ .unsupported_version = version };
    const minimum: u64 = switch (version) {
        0 => 68,
        1 => 86,
        2, 3, 4 => 96,
        else => 100,
    };
    if (r.len() < minimum) return .{ .rejected = .too_short };
    const b = r.fixed(68, 0) orelse return .{ .rejected = .too_short };
    return .{
        .valid = .{
            .version = version,
            .x_avg_char_width = b.int(i16, 2),
            .us_weight_class = b.int(u16, 4),
            .us_width_class = b.int(u16, 6),
            .fs_type = b.int(u16, 8),
            .y_subscript_x_size = b.int(i16, 10),
            .y_subscript_y_size = b.int(i16, 12),
            .y_subscript_x_offset = b.int(i16, 14),
            .y_subscript_y_offset = b.int(i16, 16),
            .y_superscript_x_size = b.int(i16, 18),
            .y_superscript_y_size = b.int(i16, 20),
            .y_superscript_x_offset = b.int(i16, 22),
            .y_superscript_y_offset = b.int(i16, 24),
            .y_strikeout_size = b.int(i16, 26),
            .y_strikeout_position = b.int(i16, 28),
            .s_family_class = b.int(i16, 30),
            .panose = b.array(10, 32),
            .ul_unicode_range1 = b.int(u32, 42),
            .ul_unicode_range2 = b.int(u32, 46),
            .ul_unicode_range3 = b.int(u32, 50),
            .ul_unicode_range4 = b.int(u32, 54),
            .ach_vend_id = b.array(4, 58),
            .fs_selection = b.int(u16, 62),
            .us_first_char_index = b.int(u16, 64),
            .us_last_char_index = b.int(u16, 66),
            // A legacy version 0 table may end at usLastCharIndex.
            .typo = if (r.fixed(10, 68)) |t| .{
                .s_typo_ascender = t.int(i16, 0),
                .s_typo_descender = t.int(i16, 2),
                .s_typo_line_gap = t.int(i16, 4),
                .us_win_ascent = t.int(u16, 6),
                .us_win_descent = t.int(u16, 8),
            } else null,
            .v1 = if (version < 1) null else blk: {
                const v = r.fixed(8, 78) orelse return .{ .rejected = .too_short };
                break :blk .{ .ul_code_page_range1 = v.int(u32, 0), .ul_code_page_range2 = v.int(u32, 4) };
            },
            .v2 = if (version < 2) null else blk: {
                const v = r.fixed(10, 86) orelse return .{ .rejected = .too_short };
                break :blk .{
                    .sx_height = v.int(i16, 0),
                    .s_cap_height = v.int(i16, 2),
                    .us_default_char = v.int(u16, 4),
                    .us_break_char = v.int(u16, 6),
                    .us_max_context = v.int(u16, 8),
                };
            },
            .v5 = if (version < 5) null else blk: {
                const v = r.fixed(4, 96) orelse return .{ .rejected = .too_short };
                break :blk .{ .us_lower_optical_point_size = v.int(u16, 0), .us_upper_optical_point_size = v.int(u16, 2) };
            },
        },
    };
}

pub const Post = struct {
    version: u32,
    /// A 16.16 fixed-point value, as stored.
    italic_angle: i32,
    underline_position: i16,
    underline_thickness: i16,
    is_fixed_pitch: u32,
    min_mem_type42: u32,
    max_mem_type42: u32,
    min_mem_type1: u32,
    max_mem_type1: u32,
};

/// A 32-byte header with version 1.0, 2.0, or 3.0. Version 2.0 also checks its glyph count and every custom name index,
/// in time linear in the table length.
pub fn parsePost(r: Reader, num_glyphs: u16) TableStatus(Post) {
    const p = r.fixed(32, 0) orelse return .{ .rejected = .too_short };
    const post: Post = .{
        .version = p.int(u32, 0),
        .italic_angle = p.int(i32, 4),
        .underline_position = p.int(i16, 8),
        .underline_thickness = p.int(i16, 10),
        .is_fixed_pitch = p.int(u32, 12),
        .min_mem_type42 = p.int(u32, 16),
        .max_mem_type42 = p.int(u32, 20),
        .min_mem_type1 = p.int(u32, 24),
        .max_mem_type1 = p.int(u32, 28),
    };
    switch (post.version) {
        0x00010000, 0x00030000 => return .{ .valid = post },
        0x00020000 => {},
        else => return .{ .unsupported_version = post.version },
    }
    const count = r.u16At(32) orelse return .{ .rejected = .too_short };
    if (count != num_glyphs) return .{ .rejected = .glyph_count_mismatch };
    const strings_at = 34 + 2 * @as(u64, count);
    if (!r.fits(34, 2 * @as(u64, count))) return .{ .rejected = .count_out_of_bounds };
    // Count the Pascal strings that lie completely inside the table.
    var strings: u64 = 0;
    var at = strings_at;
    while (r.u8At(at)) |length| {
        if (!r.fits(at + 1, length)) break;
        strings += 1;
        at += 1 + @as(u64, length);
    }
    var i: u64 = 0;
    while (i < count) : (i += 1) {
        const index = r.u16At(34 + 2 * i) orelse return .{ .rejected = .count_out_of_bounds };
        if (index >= 258 and index - 258 >= strings) return .{ .rejected = .invalid_string_index };
    }
    return .{ .valid = post };
}
