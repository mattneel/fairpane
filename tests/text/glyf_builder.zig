//! F_GLYF of the FP-0119 contract, and its variants.
//! F_GLYF is B_TT with a long `loca`, `indexToLocFormat` 1, `maxp` 1.0 with 45 glyphs, one long horizontal metric,
//! and the 45 `glyf` entries of the contract's fixture table, laid out in glyph order with no padding.

const std = @import("std");
const builder = @import("sfnt_builder.zig");
const Allocator = std.mem.Allocator;

pub const glyph_count = 45;

// Glyph IDs.
pub const box = 0;
pub const empty = 1;
pub const t1 = 2;
pub const t2 = 3;
pub const t3 = 4;
pub const tri = 5;
pub const dot = 6;
pub const c1 = 7;
pub const c2 = 8;
pub const c3 = 9;
pub const c4 = 10;
pub const c5a = 11;
pub const c5b = 12;
pub const c5c = 13;
pub const c6 = 14;
pub const c7 = 15;
pub const c8 = 16;
pub const self_reference = 26;
pub const ping = 27;
pub const pong = 28;
pub const l300 = 29;
pub const t4 = 42;
pub const c5d = 43;
pub const c9 = 44;

/// Dk, for k from 1 to 9.
pub fn d(k: u16) u16 {
    return 16 + k;
}

/// Ek, for k from 1 to 8.
pub fn e(k: u16) u16 {
    return 29 + k;
}

/// Fk, for k from 1 to 4.
pub fn f(k: u16) u16 {
    return 37 + k;
}

fn hexLength(comptime text: []const u8) usize {
    var digits: usize = 0;
    for (text) |c| {
        if (c != ' ') digits += 1;
    }
    if (digits % 2 != 0) @compileError("odd hex digit count");
    return digits / 2;
}

/// The bytes that `text` spells in hexadecimal pairs, with spaces ignored.
pub fn hex(comptime text: []const u8) *const [hexLength(text)]u8 {
    const bytes = comptime hexArray(text);
    return &bytes;
}

fn hexArray(comptime text: []const u8) [hexLength(text)]u8 {
    @setEvalBranchQuota(20 * text.len + 1000);
    var out: [hexLength(text)]u8 = undefined;
    var n: usize = 0;
    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == ' ') {
            i += 1;
            continue;
        }
        out[n] = std.fmt.parseInt(u8, text[i..][0..2], 16) catch @compileError("bad hex pair");
        n += 1;
        i += 2;
    }
    return out;
}

/// The header of every composite: numberOfContours −1 and bounds (0, 0, 0, 0).
pub const composite_header = hex("FFFF 0000 0000 0000 0000");

pub const t1_bytes = hex("0002 FF0B 0014 03E8 012C 0003 0006 0003 AABBCC 77 11 22 15 29 02 0A FF 04DD FC18 FFF6 14 0118 FF");
pub const t2_bytes = hex("0001 0000 0000 0064 0064 0003 0000 00 00 00 00 0000 0064 0000 FF9C 0000 0000 0064 0000");
pub const t3_bytes = hex("0001 0000 0000 0064 0064 0002 0000 00 01 01 0032 0032 FF9C 0064 FF9C 0000");
pub const t4_bytes = hex("0002 0005 0005 0007 0009 0000 0001 0000 37 36 05 02 05 04");
pub const c1_bytes = hex("FFFF 0000 0000 0000 0000 0002 0003 0A EC");
pub const c2_bytes = composite_header ++ hex("000B 0005 012C FED4 2000");
pub const c3_bytes = composite_header ++ hex("0042 0005 0A 00 C000 6000");
pub const c4_bytes = composite_header ++ hex("0082 0005 00 00 0000 4000 C000 0000");
pub const c5a_bytes = composite_header ++ hex("080B 0005 0064 00C8 2000");
pub const c5b_bytes = composite_header ++ hex("100B 0005 0064 00C8 2000");
pub const c5c_bytes = composite_header ++ hex("180B 0005 0064 00C8 2000");
pub const c5d_bytes = composite_header ++ hex("080F 0005 0065 00C9 2000");
pub const c6_bytes = composite_header ++ hex("0022 0005 00 00") ++ hex("0008 0006 02 02 2000");
pub const c7_bytes = composite_header ++ hex("0122 0005 00 00") ++ hex("0003 0006 00C8 0000") ++ hex("0002 01 02");
pub const c8_bytes = composite_header ++ hex("0002 0007 05 05");
pub const c9_bytes = composite_header ++ hex("0022 001D 00 00") ++ hex("0020 0006 C8 00") ++ hex("0001 0006 0101 0002");

pub const box_points = [_][2]i16{ .{ 50, 0 }, .{ 50, 700 }, .{ 450, 700 }, .{ 450, 0 } };
pub const tri_points = [_][2]i16{ .{ 0, 0 }, .{ 100, 0 }, .{ 50, 100 } };
pub const dot_points = [_][2]i16{ .{ 0, 0 }, .{ 10, 0 }, .{ 10, 10 }, .{ 0, 10 } };

/// L300 point i: (10·(i mod 2), i).
pub fn l300Point(i: usize) [2]i16 {
    return .{ @intCast(10 * (i % 2)), @intCast(i) };
}

/// One component record with byte arguments (0, 0).
fn component(w: *builder.Writer, flags: u16, glyph: u16) !void {
    try w.u16_(flags);
    try w.u16_(glyph);
    try w.u8_(0);
    try w.u8_(0);
}

/// The `glyf` entry of glyph `id` in F_GLYF.
pub fn glyphBytes(gpa: Allocator, id: u16) ![]u8 {
    var w: builder.Writer = .{ .gpa = gpa };
    errdefer w.bytes.deinit(gpa);
    switch (id) {
        box => try builder.simpleGlyph(&w, builder.glyph_boxes[0], &box_points),
        empty => {},
        t1 => try w.raw(t1_bytes),
        t2 => try w.raw(t2_bytes),
        t3 => try w.raw(t3_bytes),
        tri => try builder.simpleGlyph(&w, .{ 0, 0, 100, 100 }, &tri_points),
        dot => try builder.simpleGlyph(&w, .{ 0, 0, 10, 10 }, &dot_points),
        c1 => try w.raw(c1_bytes),
        c2 => try w.raw(c2_bytes),
        c3 => try w.raw(c3_bytes),
        c4 => try w.raw(c4_bytes),
        c5a => try w.raw(c5a_bytes),
        c5b => try w.raw(c5b_bytes),
        c5c => try w.raw(c5c_bytes),
        c6 => try w.raw(c6_bytes),
        c7 => try w.raw(c7_bytes),
        c8 => try w.raw(c8_bytes),
        // D1 places TRI; Dk places D(k−1), glyph 15 + k.
        17...25 => {
            try w.raw(composite_header);
            try component(&w, 0x0002, if (id == d(1)) tri else id - 1);
        },
        self_reference => {
            try w.raw(composite_header);
            try component(&w, 0x0002, self_reference);
        },
        ping => {
            try w.raw(composite_header);
            try component(&w, 0x0002, pong);
        },
        pong => {
            try w.raw(composite_header);
            try component(&w, 0x0002, ping);
        },
        l300 => {
            var points: [300][2]i16 = undefined;
            for (&points, 0..) |*p, i| p.* = l300Point(i);
            try builder.simpleGlyph(&w, .{ 0, 0, 10, 299 }, &points);
        },
        // Ek places glyph 28 + k twice.
        30...37 => {
            try w.raw(composite_header);
            try component(&w, 0x0022, id - 1);
            try component(&w, 0x0002, id - 1);
        },
        // F1 places glyph 1 sixteen times; Fk places glyph 36 + k sixteen times.
        38...41 => {
            const child: u16 = if (id == f(1)) empty else id - 1;
            try w.raw(composite_header);
            for (0..15) |_| try component(&w, 0x0022, child);
            try component(&w, 0x0002, child);
        },
        t4 => try w.raw(t4_bytes),
        c5d => try w.raw(c5d_bytes),
        c9 => try w.raw(c9_bytes),
        else => unreachable,
    }
    return w.finish();
}

/// A glyph whose `glyf` entry replaces the F_GLYF entry.
pub const Replacement = struct { glyph: u16, bytes: []const u8 };

/// The F_GLYF table set with `replacements` applied.
pub fn tables(gpa: Allocator, replacements: []const Replacement) !builder.TableSet {
    var set = try builder.ttTables(gpa);
    errdefer set.deinit();
    builder.writeU16(set.get("head".*)[50..][0..2], 1); // indexToLocFormat: long
    try set.putOwned("maxp".*, try builder.maxpV1(gpa, glyph_count));
    try set.putOwned("hhea".*, try builder.hheaTable(gpa, 1, 590));
    try set.putOwned("hmtx".*, try builder.hmtxTable(gpa, &.{.{ 500, 0 }}, &@as([glyph_count - 1]i16, @splat(0))));

    var glyf: builder.Writer = .{ .gpa = gpa };
    defer glyf.bytes.deinit(gpa);
    var loca: builder.Writer = .{ .gpa = gpa };
    defer loca.bytes.deinit(gpa);
    for (0..glyph_count) |i| {
        const id: u16 = @intCast(i);
        try loca.u32_(@intCast(glyf.len()));
        const replacement: ?[]const u8 = for (replacements) |r| {
            if (r.glyph == id) break r.bytes;
        } else null;
        if (replacement) |bytes| {
            try glyf.raw(bytes);
        } else {
            const bytes = try glyphBytes(gpa, id);
            defer gpa.free(bytes);
            try glyf.raw(bytes);
        }
    }
    try loca.u32_(@intCast(glyf.len()));
    try set.put("glyf".*, glyf.bytes.items);
    try set.put("loca".*, loca.bytes.items);
    return set;
}

/// Builds F_GLYF with `replacements` applied.
pub fn build(gpa: Allocator, replacements: []const Replacement) ![]u8 {
    var set = try tables(gpa, replacements);
    defer set.deinit();
    return set.build(&.{}, &.{});
}

/// The font offset of glyph `id`'s `glyf` entry in a font that `build` wrote.
pub fn glyphOffset(font_bytes: []const u8, id: u16) usize {
    const loca = builder.recordOffset(font_bytes, "loca".*);
    return builder.recordOffset(font_bytes, "glyf".*) + builder.readU32(font_bytes, loca + 4 * @as(usize, id));
}
