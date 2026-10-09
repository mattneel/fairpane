//! The OpenType `CFF ` table: the header, the Name, Top DICT, String, and Global Subr INDEXes, the Top DICT operators,
//! and the CharStrings INDEX. Charstrings are not interpreted.
//! Sources: the OpenType `cff` chapter and Adobe Technical Note #5176, "The Compact Font Format Specification".

const std = @import("std");
const Reader = @import("reader.zig").Reader;

pub const Cff = struct {
    /// The single Name INDEX entry, the PostScript font name.
    name: []const u8,
    charstrings_count: u16,
    /// Whether the Top DICT has the ROS operator (12 30), which makes the font CID-keyed.
    cid_keyed: bool,
};

const Index = struct {
    table: Reader,
    count: u16,
    off_size: u8,
    offsets_at: u64,
    /// The offset of the byte before the data, so INDEX offset 1 names the first data byte.
    data_base: u64,
    end: u64,

    /// INDEX offset `i`, or null when it lies outside the table.
    fn offsetValue(self: Index, i: u64) ?u64 {
        var value: u64 = 0;
        var k: u64 = 0;
        while (k < self.off_size) : (k += 1) value = (value << 8) | (self.table.u8At(self.offsets_at + i * self.off_size + k) orelse return null);
        return value;
    }

    /// The data of item `i`, or null when its offsets do not describe a range inside the table.
    fn item(self: Index, i: u64) ?[]const u8 {
        const start = self.data_base + (self.offsetValue(i) orelse return null);
        const end = self.data_base + (self.offsetValue(i + 1) orelse return null);
        if (end < start) return null;
        return self.table.slice(start, end - start);
    }
};

/// A nonzero count has an offSize from 1 to 4, a first offset of 1, nondecreasing offsets, and data inside the table.
fn readIndex(table: Reader, at: u64) error{InvalidCff}!Index {
    const count = table.u16At(at) orelse return error.InvalidCff;
    if (count == 0) return .{ .table = table, .count = 0, .off_size = 0, .offsets_at = at + 2, .data_base = at + 2, .end = at + 2 };
    const off_size = table.u8At(at + 2) orelse return error.InvalidCff;
    if (off_size < 1 or off_size > 4) return error.InvalidCff;
    const offsets_bytes = (@as(u64, count) + 1) * off_size;
    if (!table.fits(at + 3, offsets_bytes)) return error.InvalidCff;
    var index: Index = .{ .table = table, .count = count, .off_size = off_size, .offsets_at = at + 3, .data_base = at + 2 + offsets_bytes, .end = 0 };
    const first = index.offsetValue(0) orelse return error.InvalidCff;
    if (first != 1) return error.InvalidCff;
    var previous: u64 = 1;
    var i: u64 = 1;
    while (i <= count) : (i += 1) {
        const value = index.offsetValue(i) orelse return error.InvalidCff;
        if (value < previous) return error.InvalidCff;
        previous = value;
    }
    index.end = index.data_base + previous;
    if (index.end > table.len()) return error.InvalidCff;
    return index;
}

const max_operands = 48;

const Operand = union(enum) { integer: i32, real };

const TopDict = struct {
    charstrings: ?i32 = null,
    charstring_type: i32 = 2,
    ros: bool = false,
};

/// Parses a Top DICT with at most 48 operands per operator. Reserved bytes 22 to 27, 31, and 255 are rejected,
/// and a real operand must end with the nibble 0xF inside the DICT.
fn parseTopDict(dict: Reader) error{InvalidCff}!TopDict {
    var result: TopDict = .{};
    var operands: [max_operands]Operand = undefined;
    var depth: usize = 0;
    var at: u64 = 0;
    while (dict.u8At(at)) |b0| {
        const operand: Operand = switch (b0) {
            0...21 => {
                var operator: u16 = b0;
                at += 1;
                if (b0 == 12) {
                    operator = 1200 + @as(u16, dict.u8At(at) orelse return error.InvalidCff);
                    at += 1;
                }
                const args = operands[0..depth];
                switch (operator) {
                    17 => result.charstrings = try singleInteger(args),
                    1206 => result.charstring_type = try singleInteger(args),
                    1230 => result.ros = true,
                    else => {},
                }
                depth = 0;
                continue;
            },
            28 => blk: {
                const value = dict.i16At(at + 1) orelse return error.InvalidCff;
                at += 3;
                break :blk .{ .integer = value };
            },
            29 => blk: {
                const value = dict.i32At(at + 1) orelse return error.InvalidCff;
                at += 5;
                break :blk .{ .integer = value };
            },
            30 => blk: {
                at += 1;
                while (true) : (at += 1) {
                    const byte = dict.u8At(at) orelse return error.InvalidCff;
                    const high = byte >> 4;
                    const low = byte & 0xF;
                    if (high == 0xD or (high != 0xF and low == 0xD)) return error.InvalidCff;
                    if (high == 0xF or low == 0xF) break;
                }
                at += 1;
                break :blk .real;
            },
            32...246 => blk: {
                at += 1;
                break :blk .{ .integer = @as(i32, b0) - 139 };
            },
            247...250 => blk: {
                const b1 = dict.u8At(at + 1) orelse return error.InvalidCff;
                at += 2;
                break :blk .{ .integer = (@as(i32, b0) - 247) * 256 + b1 + 108 };
            },
            251...254 => blk: {
                const b1 = dict.u8At(at + 1) orelse return error.InvalidCff;
                at += 2;
                break :blk .{ .integer = -(@as(i32, b0) - 251) * 256 - b1 - 108 };
            },
            22...27, 31, 255 => return error.InvalidCff,
        };
        if (depth == max_operands) return error.InvalidCff;
        operands[depth] = operand;
        depth += 1;
    }
    if (depth != 0) return error.InvalidCff;
    return result;
}

fn singleInteger(args: []const Operand) error{InvalidCff}!i32 {
    if (args.len != 1) return error.InvalidCff;
    return switch (args[0]) {
        .integer => |v| v,
        .real => error.InvalidCff,
    };
}

/// Validates the CFF header, the four leading INDEXes, the Top DICT, and the CharStrings INDEX.
pub fn parse(table: Reader, num_glyphs: u16) error{InvalidCff}!Cff {
    const major = table.u8At(0) orelse return error.InvalidCff;
    const header_size = table.u8At(2) orelse return error.InvalidCff;
    const off_size = table.u8At(3) orelse return error.InvalidCff;
    if (major != 1 or header_size < 4 or header_size > table.len() or off_size < 1 or off_size > 4) return error.InvalidCff;
    const names = try readIndex(table, header_size);
    const top_dicts = try readIndex(table, names.end);
    const strings = try readIndex(table, top_dicts.end);
    _ = try readIndex(table, strings.end);
    if (names.count != 1 or top_dicts.count != 1) return error.InvalidCff;
    const dict = try parseTopDict(Reader.init(top_dicts.item(0) orelse return error.InvalidCff));
    if (dict.charstring_type != 2) return error.InvalidCff;
    const charstrings_at = dict.charstrings orelse return error.InvalidCff;
    if (charstrings_at < 0) return error.InvalidCff;
    const charstrings = try readIndex(table, @intCast(charstrings_at));
    if (charstrings.count != num_glyphs) return error.InvalidCff;
    return .{ .name = names.item(0) orelse return error.InvalidCff, .charstrings_count = charstrings.count, .cid_keyed = dict.ros };
}
