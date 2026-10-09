//! A first-party, deterministic writer of the FP-0111 layout fixtures: the GSUB and GPOS tables G, G11, P, T_MFS, and H(N),
//! the `chapter2` example tables E1, E2, and E34, the GDEF tables F_GDEF, F_GDEF4, and F_GDEF2, and the subtable byte strings.
//! `engineering/evidence/FP-0111/CONTRACT.md` defines every byte. `build` returns the position of every field that a case edits.

const std = @import("std");
const Allocator = std.mem.Allocator;
const sfnt = @import("sfnt_builder.zig");
const Writer = sfnt.Writer;

pub const Tag = sfnt.Tag;

fn hexLen(comptime text: []const u8) usize {
    var digits: usize = 0;
    for (text) |c| {
        if (c != ' ') digits += 1;
    }
    if (digits % 2 != 0) @compileError("odd number of hex digits");
    return digits / 2;
}

/// The bytes that hex `text` spells; spaces separate groups and carry no meaning.
pub fn hex(comptime text: []const u8) [hexLen(text)]u8 {
    return comptime decode(text);
}

fn decode(comptime text: []const u8) [hexLen(text)]u8 {
    @setEvalBranchQuota(20 * text.len + 1000);
    var out: [hexLen(text)]u8 = undefined;
    var at: usize = 0;
    var high: ?u8 = null;
    for (text) |c| {
        if (c == ' ') continue;
        const digit = std.fmt.charToDigit(c, 16) catch @compileError("not a hex digit");
        if (high) |upper| {
            out[at] = upper * 16 + digit;
            at += 1;
            high = null;
        } else high = digit;
    }
    return out;
}

// The subtable byte strings, each self-contained with offsets relative to its own start.
pub const ss1 = hex("0001 0006 000A 0001 0002 0002 0003");
pub const ss2 = hex("0002 000C 0003 0004 0005 0006 0002 0001 0001 0003 0000");
pub const ls = hex("0001 0008 0001 000E 0001 0001 0002 0001 0004 0005 0002 0003");
pub const cc3 = hex("0003 0001 000E 0001 0014 0000 0000 0001 0001 0001 0001 0001 0003");
pub const cx3 = hex("0003 0002 0000 000A 0010 0001 0001 0001 0001 0001 0002");
pub const e1x = hex("0001 0001 0000 0008 0001 0006 0003 0001 0001 0001");
pub const e2x = hex("0001 0001 0000 0008 0002 0008 0001 0007 0001 0001 0002");
pub const e3x = hex("0001 0004 0000 0008") ++ ls;
pub const sp1 = hex("0001 0008 0004 FFF6 0001 0001 0002");
pub const mb = hex("0001 000C 0012 0001 0018 0024 0001 0001 0003 0001 0001 0001 0001 0000 0006 0001 0000 0000 0001 0004 0001 0064 01F4");

/// E1, GSUB from `chapter2` Example 1, 46 bytes.
pub const e1 = hex("0001 0000 000A 002A 002C") ++ hex("0003 68616E69 0014 6B616E61 0018 6C61746E 001C") ++
    hex("0000 0000 0000 0000 0000 0000") ++ hex("0000") ++ hex("0000");

/// E2, GSUB from `chapter2` Example 2, 136 bytes.
pub const e2 = hex("0001 0000 000A 0034 0066") ++ hex("0001 61726162 0008") ++
    hex("000A 0001 55524420 0016 0000 FFFF 0003 0000 0001 0002 0000 0003 0003 0000 0001 0002") ++
    hex("0004 696E6974 001A 66696E61 0020 6D656469 0026 6C6F636C 002C 0000 0001 0000 0000 0001 0001 0000 0001 0002 0000 0001 0003") ++
    hex("0004 000A 0010 0016 001C") ++ hex("0001 0000 0000 0001 0000 0000 0001 0000 0000 0001 0000 0000");

/// E34, GSUB from `chapter2` Examples 3 and 4, 178 bytes.
pub const e34 = hex("0001 0000 000A 001E 004A") ++ hex("0001 44464C54 0008") ++ hex("0004 0000") ++ hex("0000 FFFF 0001 0001") ++
    hex("0003 6C696761 0014 6C696761 001A 6C696761 0022 0000 0001 0001 0000 0002 0000 0001 0000 0003 0000 0001 0002") ++
    hex("0003 0008 0010 0018 0004 000C 0001 0018 0004 000C 0001 0028 0004 000C 0001 0038") ++ ls ++ ls ++ ls;

/// F_GDEF, GDEF 1.2, 110 bytes.
pub const f_gdef = hex("0001 0002 000E 0000 0042 0024 002C") ++
    hex("0002 0003 0001 0001 0001 0002 0002 0002 0003 0003 0003") ++
    hex("0001 0003 0001 0002") ++
    hex("0001 0002 0000 000C 0000 0012 0001 0001 0003 0001 0000") ++
    hex("0006 0001 000C 0001 0001 0002 0003 0008 000C 0010 0001 025B 0002 000D 0003 04B6 0006 000C 0011 0002 1111 2200");

/// F_GDEF4, GDEF 1.0 with the `gdef` Example 4 LigCaretList, 50 bytes.
pub const f_gdef4 = hex("0001 0000 0000 0000 000C 0000") ++
    hex("0008 0002 0010 0014 0001 0002 009F 00A5 0001 000E 0002 0006 000E 0001 025B 0001 025B 0001 04B6");

/// The `gdef` Example 2 ClassDef bytes, whose ranges are not sorted by start glyph.
pub const gdef_example2 = hex("0002 0004 0024 0024 0001 009F 009F 0002 0058 0058 0003 018F 018F 0004");

/// F_GDEF2, GDEF 1.0 with the `gdef` Example 2 GlyphClassDef, 40 bytes.
pub const f_gdef2 = hex("0001 0000 000C 0000 0000 0000") ++ gdef_example2;

pub const LangSysSpec = struct { required: ?u16 = null, features: []const u16 = &.{} };
pub const LangSysRecord = struct { tag: Tag, sys: LangSysSpec };
pub const ScriptSpec = struct { tag: Tag, default: ?LangSysSpec, records: []const LangSysRecord = &.{} };
pub const FeatureSpec = struct { tag: Tag, lookups: []const u16 };
pub const LookupSpec = struct {
    lookup_type: u16,
    flag: u16 = 0,
    /// Written after the subtable offsets when not null. T_MFS sets flag 0x0010 without it.
    mark_filtering_set: ?u16 = null,
    subtables: []const []const u8,
};
pub const Spec = struct {
    minor: u16 = 0,
    scripts: []const ScriptSpec,
    features: []const FeatureSpec,
    lookups: []const LookupSpec,
};

/// The capacity of each position array.
pub const max = 16;

/// Table-relative byte positions of the structures that `build` wrote.
pub const Positions = struct {
    script_list: usize = 0,
    feature_list: usize = 0,
    lookup_list: usize = 0,
    script_records: [max]usize = @splat(0),
    scripts: [max]usize = @splat(0),
    default_lang_sys: [max]?usize = @splat(null),
    lang_sys: [max][max]usize = @splat(zeros),
    feature_records: [max]usize = @splat(0),
    features: [max]usize = @splat(0),
    lookups: [max]usize = @splat(0),
    subtables: [max][max]usize = @splat(zeros),
};

const zeros: [max]usize = @splat(0);

pub const Built = struct {
    bytes: []u8,
    at: Positions,

    pub fn deinit(self: *Built, gpa: Allocator) void {
        gpa.free(self.bytes);
        self.* = undefined;
    }
};

fn langSys(w: *Writer, sys: LangSysSpec) !void {
    try w.u16_(0); // lookupOrderOffset
    try w.u16_(sys.required orelse 0xFFFF);
    try w.u16_(@intCast(sys.features.len));
    for (sys.features) |f| try w.u16_(f);
}

/// Writes the header, the ScriptList, each Script followed by its default LangSys and its LangSys tables, the FeatureList,
/// the LookupList, each Lookup followed by its subtables, and then the Feature tables.
pub fn build(gpa: Allocator, spec: Spec) !Built {
    std.debug.assert(spec.scripts.len <= max and spec.features.len <= max and spec.lookups.len <= max);
    var w: Writer = .{ .gpa = gpa };
    errdefer w.bytes.deinit(gpa);
    var at: Positions = .{};
    try w.u16_(1);
    try w.u16_(spec.minor);
    try w.u16_(0);
    try w.u16_(0);
    try w.u16_(0);
    if (spec.minor == 1) try w.u32_(0);

    at.script_list = w.len();
    w.patchU16(4, @intCast(at.script_list));
    try w.u16_(@intCast(spec.scripts.len));
    for (spec.scripts, 0..) |s, i| {
        at.script_records[i] = w.len();
        try w.raw(&s.tag);
        try w.u16_(0);
    }
    for (spec.scripts, 0..) |s, i| {
        const script = w.len();
        at.scripts[i] = script;
        w.patchU16(at.script_records[i] + 4, @intCast(script - at.script_list));
        try w.u16_(0); // defaultLangSysOffset
        try w.u16_(@intCast(s.records.len));
        for (s.records) |r| {
            try w.raw(&r.tag);
            try w.u16_(0);
        }
        if (s.default) |sys| {
            at.default_lang_sys[i] = w.len();
            w.patchU16(script, @intCast(w.len() - script));
            try langSys(&w, sys);
        }
        for (s.records, 0..) |r, j| {
            at.lang_sys[i][j] = w.len();
            w.patchU16(script + 4 + 6 * j + 4, @intCast(w.len() - script));
            try langSys(&w, r.sys);
        }
    }

    at.feature_list = w.len();
    w.patchU16(6, @intCast(at.feature_list));
    try w.u16_(@intCast(spec.features.len));
    for (spec.features, 0..) |f, i| {
        at.feature_records[i] = w.len();
        try w.raw(&f.tag);
        try w.u16_(0);
    }

    at.lookup_list = w.len();
    w.patchU16(8, @intCast(at.lookup_list));
    try w.u16_(@intCast(spec.lookups.len));
    for (spec.lookups) |_| try w.u16_(0);
    for (spec.lookups, 0..) |l, i| {
        const lookup = w.len();
        at.lookups[i] = lookup;
        w.patchU16(at.lookup_list + 2 + 2 * i, @intCast(lookup - at.lookup_list));
        try w.u16_(l.lookup_type);
        try w.u16_(l.flag);
        try w.u16_(@intCast(l.subtables.len));
        for (l.subtables) |_| try w.u16_(0);
        if (l.mark_filtering_set) |set| try w.u16_(set);
        for (l.subtables, 0..) |s, k| {
            at.subtables[i][k] = w.len();
            w.patchU16(lookup + 6 + 2 * k, @intCast(w.len() - lookup));
            try w.raw(s);
        }
    }

    for (spec.features, 0..) |f, i| {
        at.features[i] = w.len();
        w.patchU16(at.feature_records[i] + 4, @intCast(w.len() - at.feature_list));
        try w.u16_(0); // featureParamsOffset
        try w.u16_(@intCast(f.lookups.len));
        for (f.lookups) |l| try w.u16_(l);
    }
    return .{ .bytes = try w.finish(), .at = at };
}

/// G, GSUB 1.0.
pub const g_spec: Spec = .{
    .scripts = &.{
        .{ .tag = "DFLT".*, .default = .{ .features = &.{0} }, .records = &.{.{ .tag = "ZZZ ".*, .sys = .{ .features = &.{ 0, 6 } } }} },
        .{ .tag = "arab".*, .default = .{ .required = 5, .features = &.{ 1, 0 } }, .records = &.{.{ .tag = "URD ".*, .sys = .{ .features = &.{ 1, 4 } } }} },
        .{ .tag = "latn".*, .default = null, .records = &.{
            .{ .tag = "DEU ".*, .sys = .{ .features = &.{ 2, 6 } } },
            .{ .tag = "TRK ".*, .sys = .{ .features = &.{3} } },
        } },
    },
    .features = &.{
        .{ .tag = "ccmp".*, .lookups = &.{0} },
        .{ .tag = "init".*, .lookups = &.{ 2, 1 } },
        .{ .tag = "liga".*, .lookups = &.{3} },
        .{ .tag = "liga".*, .lookups = &.{4} },
        .{ .tag = "locl".*, .lookups = &.{5} },
        .{ .tag = "rlig".*, .lookups = &.{ 6, 2 } },
        .{ .tag = "smcp".*, .lookups = &.{7} },
    },
    .lookups = &.{
        .{ .lookup_type = 1, .subtables = &.{ &ss1, &ss2 } },
        .{ .lookup_type = 4, .flag = 0x0008, .subtables = &.{&ls} },
        .{ .lookup_type = 6, .flag = 0x0010, .mark_filtering_set = 1, .subtables = &.{&cc3} },
        .{ .lookup_type = 7, .flag = 0x0200, .subtables = &.{ &e1x, &e2x } },
        .{ .lookup_type = 5, .subtables = &.{&cx3} },
        .{ .lookup_type = 9, .subtables = &.{&ss1} },
        .{ .lookup_type = 1, .subtables = &.{&hex("0003 0006 0000 0001 0000")} },
        .{ .lookup_type = 7, .subtables = &.{&(hex("0001 0007 0000 0008") ++ ss1)} },
        .{ .lookup_type = 7, .subtables = &.{ &e1x, &e3x } },
        .{ .lookup_type = 7, .subtables = &.{&(hex("0001 000A 0000 0008") ++ ss1)} },
        .{ .lookup_type = 7, .subtables = &.{&(hex("0002 0001 0000 0008") ++ ss1)} },
        .{ .lookup_type = 1, .flag = 0x00E0, .subtables = &.{&ss1} },
        .{ .lookup_type = 1, .flag = 0xFF1F, .mark_filtering_set = 0, .subtables = &.{&ss1} },
    },
};

pub fn g(gpa: Allocator) !Built {
    return build(gpa, g_spec);
}

/// G11: G as version 1.1, whose FeatureVariations offset names 8 bytes appended at the end.
pub fn g11(gpa: Allocator) !Built {
    var spec = g_spec;
    spec.minor = 1;
    var built = try build(gpa, spec);
    errdefer built.deinit(gpa);
    const end = built.bytes.len;
    built.bytes = try gpa.realloc(built.bytes, end + 8);
    @memcpy(built.bytes[end..], &hex("0001 0000 0000 0000"));
    sfnt.writeU32(built.bytes[10..14], @intCast(end));
    return built;
}

/// P, GPOS 1.0.
pub const p_spec: Spec = .{
    .scripts = &.{.{ .tag = "DFLT".*, .default = .{ .features = &.{ 0, 1 } } }},
    .features = &.{
        .{ .tag = "kern".*, .lookups = &.{ 0, 2 } },
        .{ .tag = "mark".*, .lookups = &.{1} },
    },
    .lookups = &.{
        .{ .lookup_type = 1, .subtables = &.{&sp1} },
        .{ .lookup_type = 4, .subtables = &.{&mb} },
        .{ .lookup_type = 9, .subtables = &.{&(hex("0001 0001 0000 0008") ++ sp1)} },
        .{ .lookup_type = 10, .subtables = &.{&sp1} },
        .{ .lookup_type = 8, .subtables = &.{&cc3} },
        .{ .lookup_type = 2, .subtables = &.{&hex("0003 0000")} },
        .{ .lookup_type = 9, .subtables = &.{&(hex("0001 0009 0000 0008") ++ sp1)} },
        .{ .lookup_type = 9, .subtables = &.{&(hex("0001 0004 0000 0008") ++ mb)} },
        .{ .lookup_type = 0, .subtables = &.{&sp1} },
    },
};

pub fn p(gpa: Allocator) !Built {
    return build(gpa, p_spec);
}

/// T_MFS: one lookup with flag 0x0010 and neither subtables nor a markFilteringSet field, at the end of the table.
pub fn tMfs(gpa: Allocator) !Built {
    return build(gpa, .{
        .scripts = &.{.{ .tag = "DFLT".*, .default = .{} }},
        .features = &.{},
        .lookups = &.{.{ .lookup_type = 1, .flag = 0x0010, .subtables = &.{} }},
    });
}

/// H(N): a DFLT default LangSys and a `liga` Feature that each list index 0 N times.
pub fn h(gpa: Allocator, n: u16) ![]u8 {
    var w: Writer = .{ .gpa = gpa };
    errdefer w.bytes.deinit(gpa);
    try w.raw(&hex("0001 0000 000A"));
    try w.u16_(28 + 2 * n);
    try w.u16_(36 + 2 * n);
    try w.raw(&hex("0001 44464C54 0008"));
    try w.raw(&hex("0004 0000"));
    try w.raw(&hex("0000 FFFF"));
    try w.u16_(n);
    for (0..n) |_| try w.u16_(0);
    std.debug.assert(w.len() == 28 + 2 * @as(usize, n));
    try w.raw(&hex("0001 6C696761 0012"));
    try w.raw(&hex("0001 0004 0001 0000 0000"));
    try w.raw(&hex("0000"));
    try w.u16_(n);
    for (0..n) |_| try w.u16_(0);
    return w.finish();
}
