//! An OpenType parser for a frozen table set, and a TrueType outline decoder.
//! `parse` borrows the font bytes, takes no allocator, and allocates nothing. It checks the table directory and every required
//! table, and records checksum integrity. Optional tables are checked on access and never fail the font.
//! `Font.trueTypeGlyph` decodes TrueType outlines and allocates only through its `gpa`. Hinting, CFF charstrings, and layout
//! lookups are not interpreted. Every read goes through `Reader`, offset sums use 64-bit arithmetic, no loop runs more often
//! than a count read from the input after that count is checked against the remaining bytes or a caller's budget,
//! and no function recurses.

const std = @import("std");
const reader = @import("reader.zig");
const tables = @import("tables.zig");
const cmap_mod = @import("cmap.zig");
const cff_mod = @import("cff.zig");
const layout = @import("layout.zig");
pub const outline_model = @import("outline.zig");
pub const glyf_decoder = @import("glyf.zig");

const Reader = reader.Reader;
pub const Tag = reader.Tag;
pub const Outline = tables.Outline;
pub const Defect = tables.Defect;
pub const TableStatus = tables.TableStatus;
pub const Head = tables.Head;
pub const Hhea = tables.Hhea;
pub const Maxp = tables.Maxp;
pub const MaxpV1 = tables.MaxpV1;
pub const HMetric = tables.HMetric;
pub const GlyphHeader = tables.GlyphHeader;
pub const Name = tables.Name;
pub const NameRecord = tables.NameRecord;
pub const Os2 = tables.Os2;
pub const Os2Typo = tables.Os2Typo;
pub const Os2V1 = tables.Os2V1;
pub const Os2V2 = tables.Os2V2;
pub const Os2V5 = tables.Os2V5;
pub const Post = tables.Post;
pub const CmapSubtable = cmap_mod.Subtable;
pub const CmapSelection = cmap_mod.Selection;
pub const Cff = cff_mod.Cff;
pub const Layout = layout.Layout;
pub const Gdef = layout.Gdef;

pub const ParseOptions = struct { checksums: enum { report, reject } = .report };

pub const ParseError = error{
    Truncated,
    UnknownSfntVersion,
    UnsupportedSfntVersion,
    UnsupportedCollection,
    UnsupportedWoff,
    UnsupportedWoff2,
    DuplicateTable,
    UnsortedTableDirectory,
    MisalignedTable,
    TableOutOfBounds,
    OverlappingTables,
    MissingRequiredTable,
    OutlineFormatMismatch,
    UnsupportedCff2,
    ChecksumMismatch,
    InvalidHead,
    InvalidMaxp,
    InvalidHhea,
    InvalidHmtx,
    InvalidLoca,
    InvalidCmap,
    NoUnicodeCmap,
    InvalidCff,
};

/// The tables that the parser knows. Each tag name is the table tag.
pub const KnownTag = enum { @"CFF ", CFF2, GDEF, GPOS, GSUB, @"OS/2", cmap, glyf, head, hhea, hmtx, loca, maxp, name, post };

fn knownTag(tag: Tag) ?KnownTag {
    for (std.meta.tags(KnownTag)) |known| {
        if (std.mem.eql(u8, &tag, @tagName(known))) return known;
    }
    return null;
}

pub const TableRecord = struct { tag: Tag, checksum: u32, offset: u32, length: u32 };

/// Checksum results. Under `.reject`, `parse` fails unless every check passes.
pub const Integrity = struct {
    /// Known tables whose computed checksum differs from the directory record.
    mismatched: std.EnumSet(KnownTag),
    /// The number of unknown tables whose computed checksum differs from the directory record.
    unknown_mismatches: u32,
    /// Whether the whole-file sum equals 0xB1B0AFBA, which holds when `head.checksumAdjustment` is right.
    head_adjustment_ok: bool,

    pub fn clean(self: Integrity) bool {
        return self.mismatched.count() == 0 and self.unknown_mismatches == 0 and self.head_adjustment_ok;
    }
};

pub const GlyphError = error{ GlyphOutOfRange, NotTrueType, InvalidGlyph };

const whole_file_sum: u32 = 0xB1B0AFBA;

/// The wrapping uint32 sum of `bytes`, zero-padded to a multiple of four. `skip_adjustment` treats bytes 8 to 11 as zero.
fn checksum(bytes: []const u8, skip_adjustment: bool) u32 {
    var sum: u32 = 0;
    var i: usize = 0;
    while (i + 4 <= bytes.len) : (i += 4) {
        if (skip_adjustment and i == 8) continue;
        sum +%= std.mem.readInt(u32, bytes[i..][0..4], .big);
    }
    if (i < bytes.len) {
        var word: [4]u8 = .{ 0, 0, 0, 0 };
        @memcpy(word[0 .. bytes.len - i], bytes[i..]);
        if (!(skip_adjustment and i == 8)) sum +%= std.mem.readInt(u32, &word, .big);
    }
    return sum;
}

/// The number of blocks in `WordSums`. 4097 prefix sums take 16 KiB of stack.
const checksum_blocks = 4096;

/// Prefix sums of the font's 32-bit words at most 4096 block boundaries.
/// A word range sums in time proportional to `bytes.len / 4096`, so the checksums of every unknown table,
/// which may overlap each other and the known tables, take time linear in the input length.
const WordSums = struct {
    bytes: []const u8,
    words: u64,
    block_words: u64,
    prefix: [checksum_blocks + 1]u32,

    fn init(self: *WordSums, bytes: []const u8) void {
        self.bytes = bytes;
        self.words = (@as(u64, bytes.len) + 3) / 4;
        self.block_words = @max(1, (self.words + checksum_blocks - 1) / checksum_blocks);
        self.prefix[0] = 0;
        var block: u64 = 0;
        while (block * self.block_words < self.words) : (block += 1) {
            const start = block * self.block_words;
            self.prefix[block + 1] = self.prefix[block] +% self.span(start, @min(self.words, start + self.block_words));
        }
    }

    /// Word `i` of the font, zero-padded past the end.
    fn word(self: *const WordSums, i: u64) u32 {
        const at: usize = @intCast(4 * i);
        if (at + 4 <= self.bytes.len) return std.mem.readInt(u32, self.bytes[at..][0..4], .big);
        var padded: [4]u8 = .{ 0, 0, 0, 0 };
        @memcpy(padded[0 .. self.bytes.len - at], self.bytes[at..]);
        return std.mem.readInt(u32, &padded, .big);
    }

    fn span(self: *const WordSums, start: u64, end: u64) u32 {
        var sum: u32 = 0;
        var i = start;
        while (i < end) : (i += 1) sum +%= self.word(i);
        return sum;
    }

    /// The sum of words before word `w`.
    fn before(self: *const WordSums, w: u64) u32 {
        const block = w / self.block_words;
        return self.prefix[@intCast(block)] +% self.span(block * self.block_words, w);
    }

    /// The checksum of a 4-aligned table: its whole words from the prefix sums, then its zero-padded last word.
    fn table(self: *const WordSums, offset: u32, length: u32) u32 {
        const first: u64 = offset / 4;
        const whole: u64 = length / 4;
        const sum = self.before(first + whole) -% self.before(first);
        const tail: usize = @intCast(@as(u64, offset) + 4 * whole);
        return sum +% checksum(self.bytes[tail..][0 .. length % 4], false);
    }
};

/// Compares each directory checksum with the table bytes and the whole-file sum with 0xB1B0AFBA.
/// Known tables never overlap, so summing them directly reads each byte at most once.
/// The directory was checked in the same `parse` call; a record that no longer fits counts as a mismatch.
fn checkIntegrity(r: Reader, num_tables: u16) Integrity {
    var sums: WordSums = undefined;
    sums.init(r.bytes);
    var integrity: Integrity = .{ .mismatched = .empty, .unknown_mismatches = 0, .head_adjustment_ok = sums.before(sums.words) == whole_file_sum };
    var i: u64 = 0;
    while (i < num_tables) : (i += 1) {
        const known = if (r.fixed(16, 12 + 16 * i)) |record| check: {
            const tag = knownTag(record.array(4, 0));
            const offset = record.int(u32, 8);
            const length = record.int(u32, 12);
            const bytes = r.slice(offset, length) orelse break :check tag;
            const sum = if (tag) |t| checksum(bytes, t == .head) else sums.table(offset, length);
            if (sum == record.int(u32, 4)) continue;
            break :check tag;
        } else null;
        if (known) |known_tag| integrity.mismatched.insert(known_tag) else integrity.unknown_mismatches += 1;
    }
    return integrity;
}

/// A parsed font. It borrows the font bytes, and those bytes must stay unchanged for the lifetime of the `Font`,
/// so a loader of memory that script can change, such as a `FontFace` buffer, must copy the bytes before `parse`.
/// When that rule is broken, no accessor reaches illegal behavior or reads outside the bytes: each accessor's
/// documentation states its result, which is null, glyph 0, zero, or an error.
pub const Font = struct {
    bytes: []const u8,
    outline_kind: Outline,
    num_tables: u16,
    known: std.EnumArray(KnownTag, ?TableRecord),
    integrity_result: Integrity,
    head_table: Head,
    hhea_table: Hhea,
    maxp_table: Maxp,
    hmtx_table: Reader,
    loca_table: ?tables.Loca,
    glyf_table: Reader,
    cmap_table: cmap_mod.Cmap,
    cff_table: ?Cff,

    pub fn outline(self: *const Font) Outline {
        return self.outline_kind;
    }

    pub fn tableCount(self: *const Font) u16 {
        return self.num_tables;
    }

    /// Directory record `i`, in directory order, as the bytes hold it now, or null when `i` is at or past `tableCount`.
    pub fn tableRecord(self: *const Font, i: u16) ?TableRecord {
        if (i >= self.num_tables) return null;
        const record = Reader.init(self.bytes).fixed(16, 12 + 16 * @as(u64, i)) orelse return null;
        return .{ .tag = record.array(4, 0), .checksum = record.int(u32, 4), .offset = record.int(u32, 8), .length = record.int(u32, 12) };
    }

    /// The bytes of the first table with `tag`, or null when no record has the tag or when that record no longer lies
    /// inside the font, because the bytes changed after `parse`.
    pub fn findTable(self: *const Font, tag: Tag) ?[]const u8 {
        var i: u16 = 0;
        while (i < self.num_tables) : (i += 1) {
            const record = self.tableRecord(i) orelse return null;
            if (std.mem.eql(u8, &record.tag, &tag)) return Reader.init(self.bytes).slice(record.offset, record.length);
        }
        return null;
    }

    /// A known table's bytes, from the record that `parse` checked and stored.
    fn knownTable(self: *const Font, tag: KnownTag) ?Reader {
        const record = self.known.get(tag) orelse return null;
        return Reader.init(self.bytes).sub(record.offset, record.length);
    }

    pub fn integrity(self: *const Font) Integrity {
        return self.integrity_result;
    }

    pub fn head(self: *const Font) Head {
        return self.head_table;
    }

    pub fn hhea(self: *const Font) Hhea {
        return self.hhea_table;
    }

    pub fn maxp(self: *const Font) Maxp {
        return self.maxp_table;
    }

    pub fn glyphCount(self: *const Font) u16 {
        return self.maxp_table.num_glyphs;
    }

    /// The advance width and left side bearing of `glyph`. `GlyphOutOfRange` means `glyph` is at or past numGlyphs,
    /// or that `hmtx` does not hold the metric, which `parse` rules out.
    pub fn advance(self: *const Font, glyph: u16) error{GlyphOutOfRange}!HMetric {
        if (glyph >= self.glyphCount()) return error.GlyphOutOfRange;
        return tables.hmetric(self.hmtx_table, self.hhea_table.number_of_h_metrics, glyph) orelse error.GlyphOutOfRange;
    }

    pub fn cmapSubtableCount(self: *const Font) u16 {
        return self.cmap_table.subtableCount();
    }

    /// Encoding record `i` of the `cmap` table, or null when `i` is at or past `cmapSubtableCount`, or when the record
    /// no longer names a subtable whose header fits, because the bytes changed after `parse`.
    pub fn cmapSubtable(self: *const Font, i: u16) ?CmapSubtable {
        return self.cmap_table.subtable(i);
    }

    /// The subtable that the selection order chose: (3, 10) format 12, (0, 4) format 12, (3, 1) format 4, then (0, 3) format 4.
    pub fn unicodeCmap(self: *const Font) CmapSelection {
        return self.cmap_table.selection;
    }

    /// The glyph for `code_point`, or 0 when the font does not map it or it is above U+10FFFF.
    /// The result is always below `glyphCount`; when the bytes changed after `parse`, an unreadable mapping gives glyph 0.
    pub fn glyphIndex(self: *const Font, code_point: u21) u16 {
        if (code_point > 0x10FFFF) return 0;
        return self.cmap_table.glyphIndex(code_point);
    }

    /// The `glyf` header of `glyph`, or null for an empty glyph. Only the header and contour end points are checked.
    /// `InvalidGlyph` also means that the `loca` entries no longer describe a range inside `glyf`, because the bytes changed after `parse`.
    pub fn glyphHeader(self: *const Font, glyph: u16) GlyphError!?GlyphHeader {
        if (glyph >= self.glyphCount()) return error.GlyphOutOfRange;
        const loca = self.loca_table orelse return error.NotTrueType;
        const start = loca.offset(glyph) orelse return error.InvalidGlyph;
        const end = loca.offset(@as(u64, glyph) + 1) orelse return error.InvalidGlyph;
        if (end < start) return error.InvalidGlyph;
        return tables.glyphHeader(self.glyf_table.sub(start, end - start) orelse return error.InvalidGlyph);
    }

    /// The unhinted TrueType outline of `glyph`, in font units with y pointing up, flattened across its components.
    /// `GlyphOutOfRange` means `glyph` is at or past numGlyphs, and `NotTrueType` means the font has CFF outlines.
    /// A zero-length `loca` range is an empty glyph. `InvalidGlyph` also means that a `loca` range no longer lies inside
    /// `glyf`, because the bytes changed after `parse`. Point matching against a phantom point returns
    /// `UnsupportedPhantomPoint`. Every allocation goes through `gpa`, and the caller frees the result with `deinit`.
    pub fn trueTypeGlyph(self: *const Font, gpa: std.mem.Allocator, glyph: u16, limits: outline_model.Limits) outline_model.OutlineError!glyf_decoder.TrueTypeGlyph {
        return glyf_decoder.decode(.{ .glyf = self.glyf_table, .loca = self.loca_table, .num_glyphs = self.glyphCount() }, gpa, glyph, limits);
    }

    /// Each call checks the `name` table again, in time linear in its length.
    pub fn name(self: *const Font) TableStatus(Name) {
        return tables.parseName(self.knownTable(.name) orelse return .absent);
    }

    /// Each call reads the `OS/2` table again, in constant time.
    pub fn os2(self: *const Font) TableStatus(Os2) {
        return tables.parseOs2(self.knownTable(.@"OS/2") orelse return .absent);
    }

    /// Each call checks the `post` table again, in time linear in its length.
    pub fn post(self: *const Font) TableStatus(Post) {
        return tables.parsePost(self.knownTable(.post) orelse return .absent, self.glyphCount());
    }

    /// Each call reads the `GDEF` header again, in constant time.
    pub fn gdef(self: *const Font) TableStatus(Gdef) {
        return layout.parseGdef(self.knownTable(.GDEF) orelse return .absent);
    }

    /// Each call checks the `GSUB` table again, in time linear in its length.
    pub fn gsub(self: *const Font) TableStatus(Layout) {
        return layout.parseLayout(self.knownTable(.GSUB) orelse return .absent);
    }

    /// Each call checks the `GPOS` table again, in time linear in its length.
    pub fn gpos(self: *const Font) TableStatus(Layout) {
        return layout.parseLayout(self.knownTable(.GPOS) orelse return .absent);
    }

    /// The CFF table of a CFF font, or null for a TrueType font.
    pub fn cff(self: *const Font) ?Cff {
        return self.cff_table;
    }
};

/// Parses `bytes`, which the returned `Font` borrows. `parse` takes no allocator and allocates nothing.
pub fn parse(bytes: []const u8, options: ParseOptions) ParseError!Font {
    const r = Reader.init(bytes);
    const header = r.fixed(12, 0) orelse return error.Truncated;
    const outline: Outline = switch (header.int(u32, 0)) {
        0x00010000 => .truetype,
        0x4F54544F => .cff, // "OTTO"
        0x74746366 => return error.UnsupportedCollection, // "ttcf"
        0x774F4646 => return error.UnsupportedWoff, // "wOFF"
        0x774F4632 => return error.UnsupportedWoff2, // "wOF2"
        0x74727565, 0x74797031 => return error.UnsupportedSfntVersion, // "true" and "typ1"
        else => return error.UnknownSfntVersion,
    };
    // searchRange, entrySelector, and rangeShift are ignored; the directory length follows from numTables.
    const num_tables = header.int(u16, 4);
    if (!r.fits(12, 16 * @as(u64, num_tables))) return error.Truncated;

    var known = std.EnumArray(KnownTag, ?TableRecord).initFill(null);
    var previous: Tag = undefined;
    var i: u64 = 0;
    while (i < num_tables) : (i += 1) {
        const fields = r.fixed(16, 12 + 16 * i) orelse return error.Truncated;
        const record: TableRecord = .{ .tag = fields.array(4, 0), .checksum = fields.int(u32, 4), .offset = fields.int(u32, 8), .length = fields.int(u32, 12) };
        if (i > 0) switch (std.mem.order(u8, &previous, &record.tag)) {
            .lt => {},
            .eq => return error.DuplicateTable,
            .gt => return error.UnsortedTableDirectory,
        };
        previous = record.tag;
        if (!r.fits(record.offset, record.length)) return error.TableOutOfBounds;
        if (record.offset % 4 != 0) return error.MisalignedTable;
        if (knownTag(record.tag)) |tag| known.set(tag, record);
    }

    // Known tables never overlap; an unknown table may, because the parser never reads it.
    const all = std.meta.tags(KnownTag);
    for (all, 0..) |a, ai| {
        const ra = known.get(a) orelse continue;
        if (ra.length == 0) continue;
        for (all[ai + 1 ..]) |b| {
            const rb = known.get(b) orelse continue;
            if (rb.length == 0) continue;
            if (@as(u64, ra.offset) < @as(u64, rb.offset) + rb.length and @as(u64, rb.offset) < @as(u64, ra.offset) + ra.length) {
                return error.OverlappingTables;
            }
        }
    }

    const required_common = [_]KnownTag{ .cmap, .head, .hhea, .hmtx, .maxp };
    for (required_common) |tag| if (known.get(tag) == null) return error.MissingRequiredTable;
    switch (outline) {
        .truetype => {
            if (known.get(.glyf) == null or known.get(.loca) == null) return error.MissingRequiredTable;
            if (known.get(.@"CFF ") != null or known.get(.CFF2) != null) return error.OutlineFormatMismatch;
        },
        .cff => {
            if (known.get(.@"CFF ") == null) return error.MissingRequiredTable;
            if (known.get(.glyf) != null or known.get(.loca) != null) return error.OutlineFormatMismatch;
            if (known.get(.CFF2) != null) return error.UnsupportedCff2;
        },
    }

    const integrity = checkIntegrity(r, num_tables);
    if (options.checksums == .reject and !integrity.clean()) return error.ChecksumMismatch;

    // Every required table was found above, so `table` fails only if that check is changed.
    const table = struct {
        fn get(b: []const u8, k: std.EnumArray(KnownTag, ?TableRecord), tag: KnownTag) error{MissingRequiredTable}!Reader {
            const record = k.get(tag) orelse return error.MissingRequiredTable;
            return Reader.init(b).sub(record.offset, record.length) orelse error.MissingRequiredTable;
        }
    }.get;
    const head = try tables.parseHead(try table(bytes, known, .head), outline);
    const maxp = try tables.parseMaxp(try table(bytes, known, .maxp), outline);
    const hhea = try tables.parseHhea(try table(bytes, known, .hhea), maxp.num_glyphs);
    const hmtx = try table(bytes, known, .hmtx);
    try tables.checkHmtx(hmtx, hhea.number_of_h_metrics, maxp.num_glyphs);
    var loca: ?tables.Loca = null;
    var glyf = Reader.init(&.{});
    if (outline == .truetype) {
        glyf = try table(bytes, known, .glyf);
        loca = try tables.parseLoca(try table(bytes, known, .loca), head.index_to_loc_format, maxp.num_glyphs, glyf.len());
    }
    const cmap = try cmap_mod.parse(try table(bytes, known, .cmap), maxp.num_glyphs);
    const cff = if (outline == .cff) try cff_mod.parse(try table(bytes, known, .@"CFF "), maxp.num_glyphs) else null;

    return .{
        .bytes = bytes,
        .outline_kind = outline,
        .num_tables = num_tables,
        .known = known,
        .integrity_result = integrity,
        .head_table = head,
        .hhea_table = hhea,
        .maxp_table = maxp,
        .hmtx_table = hmtx,
        .loca_table = loca,
        .glyf_table = glyf,
        .cmap_table = cmap,
        .cff_table = cff,
    };
}

test {
    _ = reader;
    _ = outline_model;
    _ = glyf_decoder;
}

test "block word sums equal the direct checksum, the reference path, for every aligned table range" {
    var bytes: [4 * checksum_blocks * 3 + 7]u8 = undefined;
    for (&bytes, 0..) |*b, i| b.* = @truncate(i *% 2654435761 >> 13);
    for ([_]usize{ 13, 400, bytes.len }) |len| {
        var sums: WordSums = undefined;
        sums.init(bytes[0..len]);
        try std.testing.expectEqual(checksum(bytes[0..len], false), sums.before(sums.words));
        var offset: usize = 0;
        while (offset < len) : (offset += 4 * 97) {
            for ([_]usize{ 0, 1, 2, 3, 4, 5, 4097, 12291, len - offset }) |length| {
                if (offset + length > len) continue;
                try std.testing.expectEqual(
                    checksum(bytes[offset..][0..length], false),
                    sums.table(@intCast(offset), @intCast(length)),
                );
            }
        }
    }
}
