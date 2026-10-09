//! FP-0111 case 25: each fixture font's GDEF classes, mark glyph sets, and ligature carets, and its GSUB and GPOS scripts,
//! features, lookups, subtable formats, and primary coverages, against the version 2 fontTools expectation files.
//! A difference prints the font, the table, the JSON path, and both values.

const std = @import("std");
const testing = std.testing;
const fairpane = @import("fairpane");
const font = fairpane.font;
const layout = font.layout;
const fixtures = @import("fixtures.zig");
const Value = std.json.Value;
const Allocator = std.mem.Allocator;

/// Where a comparison is: the fixture directory, the table, and the JSON path inside that table's object.
const Where = struct {
    font: []const u8,
    table: []const u8,
    path: []const u8,

    fn at(self: Where, arena: Allocator, comptime fmt: []const u8, args: anytype) !Where {
        return .{ .font = self.font, .table = self.table, .path = try std.fmt.allocPrint(arena, "{s}" ++ fmt, .{self.path} ++ args) };
    }

    fn fail(self: Where, comptime fmt: []const u8, args: anytype) error{TestUnexpectedResult} {
        std.debug.print("{s} {s} {s}: " ++ fmt ++ "\n", .{ self.font, self.table, self.path } ++ args);
        return error.TestUnexpectedResult;
    }

    fn int(self: Where, expected: i64, actual: i64) !void {
        if (expected != actual) return self.fail("expected {d}, parser {d}", .{ expected, actual });
    }

    fn optional(self: Where, expected: Value, actual: anytype) !void {
        const want: ?i64 = if (expected == .null) null else expected.integer;
        const got: ?i64 = if (actual) |a| @intCast(a) else null;
        if (!std.meta.eql(want, got)) return self.fail("expected {?d}, parser {?d}", .{ want, got });
    }

    fn boolean(self: Where, expected: bool, actual: bool) !void {
        if (expected != actual) return self.fail("expected {}, parser {}", .{ expected, actual });
    }

    fn tag(self: Where, expected: []const u8, actual: ?[4]u8) !void {
        const got = actual orelse return self.fail("expected {s}, parser null", .{expected});
        if (!std.mem.eql(u8, expected, &got)) return self.fail("expected {s}, parser {s}", .{ expected, &got });
    }

    fn valid(self: Where, status: anytype) !@FieldType(@TypeOf(status), "valid") {
        return switch (status) {
            .valid => |v| v,
            else => |s| self.fail("expected valid, parser {s}", .{@tagName(std.meta.activeTag(s))}),
        };
    }

    fn some(self: Where, value: anytype) !@typeInfo(@TypeOf(value)).optional.child {
        return value orelse self.fail("expected a value, parser null", .{});
    }
};

fn int(v: Value) i64 {
    return v.integer;
}

fn items(v: Value) []const Value {
    return v.array.items;
}

fn checkCoverage(w: Where, expected: Value, c: layout.Coverage) !void {
    const o = expected.object;
    try w.int(int(o.get("format").?), c.format);
    const glyphs = items(o.get("glyphs").?);
    try w.int(@intCast(glyphs.len), c.glyphCount());
    var it = c.iterator();
    for (glyphs, 0..) |g, i| {
        const next = it.next() orelse return w.fail("the iterator ends at {d}, expected glyph {d}", .{ i, int(g) });
        if (next != int(g)) return w.fail("glyph {d}: expected {d}, parser {d}", .{ i, int(g), next });
        const index = c.index(@intCast(int(g)));
        if (index == null or index.? != i) return w.fail("index of glyph {d}: expected {d}, parser {?d}", .{ int(g), i, index });
    }
    if (it.next()) |extra| return w.fail("the iterator gives the extra glyph {d}", .{extra});
}

fn checkLangSys(w: Where, expected: Value, ls: layout.LangSys) !void {
    const o = expected.object;
    try w.optional(o.get("required_feature").?, ls.required_feature);
    const features = items(o.get("features").?);
    try w.int(@intCast(features.len), ls.feature_index_count);
    for (features, 0..) |f, k| try w.optional(f, ls.featureIndex(@intCast(k)));
}

/// The stored LookupType of an extension lookup.
fn extensionType(kind: layout.Kind) u16 {
    return switch (kind) {
        .gsub => 7,
        .gpos => 9,
    };
}

const LangSysRef = struct { language: ?[]const u8, lang_sys: Value };

/// Requests the distinct feature tags of one LangSys, in first-occurrence order, and compares every mask with the masks
/// that the selection rules give for the dumped script, feature, and lookup lists.
fn crossCheck(arena: Allocator, w: Where, l: layout.Layout, features: []const Value, script: []const u8, ref: LangSysRef) !void {
    const o = ref.lang_sys.object;
    const indices = items(o.get("features").?);
    var tags: std.ArrayList([4]u8) = .empty;
    for (indices) |f| {
        const t = features[@intCast(int(f))].object.get("tag").?.string;
        const tag = t[0..4].*;
        for (tags.items) |seen| {
            if (std.mem.eql(u8, &seen, &tag)) break;
        } else try tags.append(arena, tag);
    }
    if (tags.items.len > 63) return w.fail("the LangSys names {d} distinct feature tags, more than 63", .{tags.items.len});

    const expected = try arena.alloc(u64, l.lookupCount());
    @memset(expected, 0);
    const bitsOf = struct {
        fn bits(request: []const [4]u8, tag: []const u8) u64 {
            var b: u64 = 0;
            for (request, 0..) |r, p| {
                if (std.mem.eql(u8, &r, tag)) b |= @as(u64, 1) << @intCast(p);
            }
            return b;
        }
    }.bits;
    for (indices) |f| {
        const feature = features[@intCast(int(f))].object;
        const b = bitsOf(tags.items, feature.get("tag").?.string);
        for (items(feature.get("lookups").?)) |i| expected[@intCast(int(i))] |= b;
    }
    const required = o.get("required_feature").?;
    if (required != .null) {
        const feature = features[@intCast(int(required))].object;
        const b = (@as(u64, 1) << 63) | bitsOf(tags.items, feature.get("tag").?.string);
        for (items(feature.get("lookups").?)) |i| expected[@intCast(int(i))] |= b;
    }

    const masks = try arena.alloc(u64, l.lookupCount());
    const request: layout.Request = .{
        .script = script[0..4].*,
        .language = if (ref.language) |t| t[0..4].* else null,
        .features = tags.items,
    };
    const s = try w.valid(try l.selectLookups(request, .{}, masks));
    try w.tag(script, s.script);
    if (s.lang_sys != @as(@TypeOf(s.lang_sys), if (ref.language == null) .default else .requested)) return w.fail("selection used {s}", .{@tagName(s.lang_sys)});
    try w.optional(required, s.required_feature);
    try w.boolean(false, s.feature_variations);
    var nonzero: i64 = 0;
    for (expected, masks, 0..) |e, m, i| {
        if (e != m) return w.fail("mask {d}: expected 0x{x}, parser 0x{x}", .{ i, e, m });
        if (e != 0) nonzero += 1;
    }
    try w.int(nonzero, s.lookup_count);
}

fn checkLayout(arena: Allocator, w: Where, expected: Value, status: font.TableStatus(layout.Layout)) !usize {
    if (expected == .null) {
        if (status != .absent) return w.fail("expected absent, parser {s}", .{@tagName(std.meta.activeTag(status))});
        return 0;
    }
    const l = try w.valid(status);
    const o = expected.object;
    try (try w.at(arena, ".version", .{})).int(int(o.get("version").?), l.version);
    try (try w.at(arena, ".feature_variations", .{})).boolean(o.get("feature_variations").?.bool, l.feature_variations != 0);

    const scripts = items(o.get("scripts").?);
    const features = items(o.get("features").?);
    const lookups = items(o.get("lookups").?);
    try (try w.at(arena, ".scripts.len", .{})).int(@intCast(scripts.len), l.scriptCount());
    try (try w.at(arena, ".features.len", .{})).int(@intCast(features.len), l.featureCount());
    try (try w.at(arena, ".lookups.len", .{})).int(@intCast(lookups.len), l.lookupCount());

    for (scripts, 0..) |script, i| {
        const ws = try w.at(arena, ".scripts[{d}]", .{i});
        const so = script.object;
        const s = try ws.valid(try ws.some(l.script(@intCast(i))));
        const tag = so.get("tag").?.string;
        try (try ws.at(arena, ".tag", .{})).tag(tag, s.tag);
        const default = so.get("default_lang_sys").?;
        const wd = try ws.at(arena, ".default_lang_sys", .{});
        if (default == .null) {
            if (s.defaultLangSys() != .absent) return wd.fail("expected absent", .{});
        } else {
            try checkLangSys(wd, default, try wd.valid(s.defaultLangSys()));
            try crossCheck(arena, wd, l, features, tag, .{ .language = null, .lang_sys = default });
        }
        const records = items(so.get("lang_sys").?);
        try (try ws.at(arena, ".lang_sys.len", .{})).int(@intCast(records.len), s.lang_sys_count);
        for (records, 0..) |r, j| {
            const wr = try ws.at(arena, ".lang_sys[{d}]", .{j});
            const language = r.object.get("tag").?.string;
            try (try wr.at(arena, ".tag", .{})).tag(language, s.langSysTag(@intCast(j)));
            try checkLangSys(wr, r, try wr.valid(try wr.some(s.langSys(@intCast(j)))));
            try crossCheck(arena, wr, l, features, tag, .{ .language = language, .lang_sys = r });
        }
    }

    for (features, 0..) |feature, i| {
        const wf = try w.at(arena, ".features[{d}]", .{i});
        const f = try wf.valid(try wf.some(l.feature(@intCast(i))));
        try (try wf.at(arena, ".tag", .{})).tag(feature.object.get("tag").?.string, f.tag);
        const indices = items(feature.object.get("lookups").?);
        try (try wf.at(arena, ".lookups.len", .{})).int(@intCast(indices.len), f.lookup_index_count);
        for (indices, 0..) |index, k| try (try wf.at(arena, ".lookups[{d}]", .{k})).optional(index, f.lookupIndex(@intCast(k)));
    }

    for (lookups, 0..) |lookup, i| {
        const wl = try w.at(arena, ".lookups[{d}]", .{i});
        const lo = lookup.object;
        const parsed = try wl.valid(try wl.some(l.lookup(@intCast(i))));
        const stored: u16 = if (parsed.extension) extensionType(l.kind) else parsed.lookup_type;
        try (try wl.at(arena, ".type", .{})).int(int(lo.get("type").?), stored);
        try (try wl.at(arena, ".flag", .{})).int(int(lo.get("flag").?), parsed.flag);
        try (try wl.at(arena, ".mark_filtering_set", .{})).optional(lo.get("mark_filtering_set").?, parsed.mark_filtering_set);
        const subtables = items(lo.get("subtables").?);
        try (try wl.at(arena, ".subtables.len", .{})).int(@intCast(subtables.len), parsed.subtable_count);
        for (subtables, 0..) |subtable, k| {
            const wt = try wl.at(arena, ".subtables[{d}]", .{k});
            const to = subtable.object;
            const s = try wt.valid(try wt.some(parsed.subtable(@intCast(k))));
            try (try wt.at(arena, ".extension", .{})).boolean(to.get("extension").?.bool, parsed.extension);
            try (try wt.at(arena, ".type", .{})).int(int(to.get("type").?), parsed.lookup_type);
            try (try wt.at(arena, ".format", .{})).int(int(to.get("format").?), s.format);
            const wc = try wt.at(arena, ".coverage", .{});
            try checkCoverage(wc, to.get("coverage").?, try wc.valid(s.coverage()));
        }
    }
    return lookups.len;
}

fn checkClassDef(arena: Allocator, w: Where, expected: Value, status: font.TableStatus(layout.ClassDef), num_glyphs: u16) !void {
    if (expected == .null) {
        if (status != .absent) return w.fail("expected absent, parser {s}", .{@tagName(std.meta.activeTag(status))});
        return;
    }
    const c = try w.valid(status);
    try (try w.at(arena, ".format", .{})).int(int(expected.object.get("format").?), c.format);
    const classes = try arena.alloc(u16, num_glyphs);
    @memset(classes, 0);
    for (items(expected.object.get("classes").?)) |pair| {
        const glyph: u16 = @intCast(int(items(pair)[0]));
        const class: u16 = @intCast(int(items(pair)[1]));
        if (glyph < num_glyphs) classes[glyph] = class else if (c.class(glyph) != class) {
            return w.fail("glyph {d}: expected class {d}, parser {d}", .{ glyph, class, c.class(glyph) });
        }
    }
    for (classes, 0..) |class, g| {
        if (c.class(@intCast(g)) != class) return w.fail("glyph {d}: expected class {d}, parser {d}", .{ g, class, c.class(@intCast(g)) });
    }
}

fn checkCaret(w: Where, expected: Value, status: ?layout.CaretStatus) !void {
    const caret = try w.valid(try w.some(status));
    const o = expected.object;
    switch (int(o.get("format").?)) {
        1 => switch (caret) {
            .coordinate => |c| try w.int(int(o.get("coordinate").?), c),
            else => return w.fail("expected format 1, parser {s}", .{@tagName(caret)}),
        },
        2 => switch (caret) {
            .point => |p| try w.int(int(o.get("point").?), p),
            else => return w.fail("expected format 2, parser {s}", .{@tagName(caret)}),
        },
        3 => switch (caret) {
            .coordinate_device => |cd| {
                try w.int(int(o.get("coordinate").?), cd.coordinate);
                const device = o.get("device").?;
                if (device == .null) {
                    if (cd.device != null) return w.fail("expected no device", .{});
                    return;
                }
                const d = device.object;
                const delta_format = int(d.get("delta_format").?);
                const start: u16 = @intCast(int(d.get("start_size").?));
                const end: u16 = @intCast(int(d.get("end_size").?));
                const want: layout.DeviceStatus = if (delta_format == 0x8000)
                    .{ .unsupported_variation_index = .{ .outer = start, .inner = end } }
                else
                    .{ .unsupported_device = .{ .start_size = start, .end_size = end, .delta_format = @intCast(delta_format) } };
                const got = cd.device orelse return w.fail("expected a device, parser none", .{});
                if (!std.meta.eql(want, got)) return w.fail("expected device {any}, parser {any}", .{ want, got });
            },
            else => return w.fail("expected format 3, parser {s}", .{@tagName(caret)}),
        },
        else => |f| return w.fail("unknown dumped caret format {d}", .{f}),
    }
}

fn checkGdef(arena: Allocator, w: Where, expected: Value, status: font.TableStatus(layout.Gdef), num_glyphs: u16) !void {
    if (expected == .null) {
        if (status != .absent) return w.fail("expected absent, parser {s}", .{@tagName(std.meta.activeTag(status))});
        return;
    }
    const gdef = try w.valid(status);
    const o = expected.object;
    try (try w.at(arena, ".version", .{})).int(int(o.get("version").?), gdef.version);
    try (try w.at(arena, ".item_var_store", .{})).boolean(o.get("item_var_store").?.bool, (gdef.item_var_store orelse 0) != 0);
    try checkClassDef(arena, try w.at(arena, ".glyph_class_def", .{}), o.get("glyph_class_def").?, gdef.glyphClasses(), num_glyphs);
    try checkClassDef(arena, try w.at(arena, ".mark_attach_class_def", .{}), o.get("mark_attach_class_def").?, gdef.markAttachClasses(), num_glyphs);

    const wm = try w.at(arena, ".mark_glyph_sets", .{});
    const sets = o.get("mark_glyph_sets").?;
    if (sets == .null) {
        if (gdef.markGlyphSets() != .absent) return wm.fail("expected absent", .{});
    } else {
        try (try wm.at(arena, ".format", .{})).int(int(sets.object.get("format").?), 1);
        const parsed = try wm.valid(gdef.markGlyphSets());
        const list = items(sets.object.get("sets").?);
        try (try wm.at(arena, ".sets.len", .{})).int(@intCast(list.len), parsed.count);
        for (list, 0..) |set, i| {
            const ws = try wm.at(arena, ".sets[{d}]", .{i});
            try checkCoverage(ws, set, try ws.valid(try ws.some(parsed.set(@intCast(i)))));
        }
    }

    const wc = try w.at(arena, ".lig_caret_list", .{});
    const list = o.get("lig_caret_list").?;
    if (list == .null) {
        if (gdef.ligatureCaretList() != .absent) return wc.fail("expected absent", .{});
        return;
    }
    const parsed = try wc.valid(gdef.ligatureCaretList());
    const covered = try arena.alloc(bool, num_glyphs);
    @memset(covered, false);
    for (items(list), 0..) |entry, i| {
        const we = try wc.at(arena, "[{d}]", .{i});
        const glyph: u16 = @intCast(int(entry.object.get("glyph").?));
        if (glyph < num_glyphs) covered[glyph] = true;
        const lig = try we.valid(parsed.carets(glyph));
        const carets = items(entry.object.get("carets").?);
        try (try we.at(arena, ".carets.len", .{})).int(@intCast(carets.len), lig.caret_count);
        for (carets, 0..) |caret, k| try checkCaret(try we.at(arena, ".carets[{d}]", .{k}), caret, lig.caret(@intCast(k)));
    }
    for (covered, 0..) |is_covered, g| {
        if (!is_covered and parsed.carets(@intCast(g)) != .not_covered) return wc.fail("glyph {d} is not listed but is covered", .{g});
    }
}

const LookupCounts = struct { dir: []const u8, gsub: usize, gpos: usize };
const lookup_counts = [_]LookupCounts{
    .{ .dir = "noto-sans", .gsub = 48, .gpos = 16 },
    .{ .dir = "noto-sans-arabic", .gsub = 41, .gpos = 22 },
    .{ .dir = "noto-sans-devanagari", .gsub = 171, .gpos = 28 },
    .{ .dir = "noto-sans-cjk-jp-subset", .gsub = 11, .gpos = 6 },
};

fn checkFixture(arena: Allocator, f: fixtures.Font) !void {
    const root = try std.json.parseFromSliceLeaky(Value, arena, f.expectation, .{});
    const e = root.object;
    try testing.expectEqual(@as(i64, 2), int(e.get("version").?));
    const parsed = try font.parse(f.bytes, .{ .checksums = .reject });
    const num_glyphs = parsed.glyphCount();
    const counts = for (lookup_counts) |c| {
        if (std.mem.eql(u8, c.dir, f.dir)) break c;
    } else return error.TestUnexpectedResult;
    const gsub = try checkLayout(arena, .{ .font = f.dir, .table = "gsub", .path = "" }, e.get("gsub").?, parsed.gsub());
    const gpos = try checkLayout(arena, .{ .font = f.dir, .table = "gpos", .path = "" }, e.get("gpos").?, parsed.gpos());
    try testing.expectEqual(counts.gsub, gsub);
    try testing.expectEqual(counts.gpos, gpos);
    try checkGdef(arena, .{ .font = f.dir, .table = "gdef", .path = "" }, e.get("gdef").?, parsed.gdef(), num_glyphs);
}

test "FP-0111 case 25: each fixture's GDEF, GSUB, and GPOS structures equal its version 2 fontTools dump" {
    for (fixtures.fonts) |f| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        try checkFixture(arena.allocator(), f);
    }
    const cjk = fixtures.font("noto-sans-cjk-jp-subset").?;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const root = try std.json.parseFromSliceLeaky(Value, arena.allocator(), cjk.expectation, .{});
    try testing.expect(root.object.get("gdef").? == .null);
    try testing.expect((try font.parse(cjk.bytes, .{ .checksums = .reject })).gdef() == .absent);
}
