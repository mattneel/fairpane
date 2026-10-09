//! The TrueType `glyf` outline decoder: simple glyphs, composite glyphs, and the contour-to-path conversion.
//! The decoder is unhinted. It skips glyph instructions, never executes them, and ignores `ROUND_XY_TO_GRID`.
//! Composite traversal uses a fixed array of `max_composite_depth` frames, so native stack use is constant,
//! and no function here recurses. Every read goes through `Reader`, and every allocation goes through the caller's `gpa`.

const std = @import("std");
const builtin = @import("builtin");
const reader = @import("reader.zig");
const tables = @import("tables.zig");
const outline = @import("outline.zig");

const Allocator = std.mem.Allocator;
const Reader = reader.Reader;
const Point = outline.Point;
const Verb = outline.Verb;
const Path = outline.Path;
const Limits = outline.Limits;
const OutlineError = outline.OutlineError;
const max_composite_depth = outline.max_composite_depth;

/// Decoding work: 1 for each component record, each simple-glyph instantiation, and each decoded point.
/// Each decode resets it. The counter exists only in test builds.
pub var work: if (builtin.is_test) u64 else void = if (builtin.is_test) 0 else {};

fn countWork() void {
    if (builtin.is_test) work += 1;
}

/// A decoded TrueType outline, flattened across every component.
pub const TrueTypeGlyph = struct {
    points: []Point,
    on_curve: []bool,
    /// Strictly increasing indices into `points`, one for the last point of each contour.
    contour_ends: []u32,
    /// The composite nesting depth: 0 for a simple or empty glyph, and 1 for a composite of simple glyphs.
    depth: u8,
    /// The component records of the top-level composite: 0 for a simple or empty glyph.
    top_level_components: u32,

    pub fn deinit(glyph: *TrueTypeGlyph, gpa: Allocator) void {
        gpa.free(glyph.points);
        gpa.free(glyph.on_curve);
        gpa.free(glyph.contour_ends);
        glyph.* = undefined;
    }

    /// Converts each contour to a closed subpath of lines and quadratic curves.
    /// A contour starts at its first point when that point is on the curve, else at its last point when that point is on
    /// the curve, else at the midpoint of its last and first points. Consecutive off-curve points imply an on-curve midpoint.
    pub fn path(glyph: *const TrueTypeGlyph, gpa: Allocator) error{OutOfMemory}!Path {
        // Each contour of m points emits at most m + 3 verbs and 2m + 3 points.
        const contours = glyph.contour_ends.len;
        var verbs: std.ArrayList(Verb) = .empty;
        defer verbs.deinit(gpa);
        var points: std.ArrayList(Point) = .empty;
        defer points.deinit(gpa);
        try verbs.ensureTotalCapacityPrecise(gpa, glyph.points.len + 3 * contours);
        try points.ensureTotalCapacityPrecise(gpa, 2 * glyph.points.len + 3 * contours);

        var first: usize = 0;
        for (glyph.contour_ends) |end_index| {
            const end: usize = end_index;
            const q = glyph.points[first .. end + 1];
            const on = glyph.on_curve[first .. end + 1];
            const m = q.len;
            var start: Point = undefined;
            var rest_from: usize = 0;
            var rest_to: usize = m;
            if (on[0]) {
                start = q[0];
                rest_from = 1;
            } else if (on[m - 1]) {
                start = q[m - 1];
                rest_to = m - 1;
            } else {
                start = midpoint(q[m - 1], q[0]);
            }
            verbs.appendAssumeCapacity(.move);
            points.appendAssumeCapacity(start);
            var control: ?Point = null;
            for (q[rest_from..rest_to], on[rest_from..rest_to]) |p, p_on| {
                if (p_on) {
                    if (control) |c| {
                        verbs.appendAssumeCapacity(.quad);
                        points.appendSliceAssumeCapacity(&.{ c, p });
                        control = null;
                    } else {
                        verbs.appendAssumeCapacity(.line);
                        points.appendAssumeCapacity(p);
                    }
                } else {
                    if (control) |c| {
                        verbs.appendAssumeCapacity(.quad);
                        points.appendSliceAssumeCapacity(&.{ c, midpoint(c, p) });
                    }
                    control = p;
                }
            }
            if (control) |c| {
                verbs.appendAssumeCapacity(.quad);
                points.appendSliceAssumeCapacity(&.{ c, start });
            }
            verbs.appendAssumeCapacity(.close);
            first = end + 1;
        }
        const verb_slice = try verbs.toOwnedSlice(gpa);
        errdefer gpa.free(verb_slice);
        return .{ .verbs = verb_slice, .points = try points.toOwnedSlice(gpa) };
    }
};

fn midpoint(a: Point, b: Point) Point {
    return .{ .x = (a.x + b.x) / 2, .y = (a.y + b.y) / 2 };
}

/// The tables that the decoder reads, from a parsed TrueType font. `loca` is null for a CFF font.
pub const Source = struct {
    glyf: Reader,
    loca: ?tables.Loca,
    num_glyphs: u16,

    /// The `glyf` bytes of `glyph`, which is below numGlyphs. `InvalidGlyph` means that the `loca` entries no longer
    /// describe a range inside `glyf`, because the bytes changed after `parse`.
    fn glyphData(source: Source, loca: tables.Loca, glyph: u16) OutlineError!Reader {
        const start = loca.offset(glyph) orelse return error.InvalidGlyph;
        const end = loca.offset(@as(u64, glyph) + 1) orelse return error.InvalidGlyph;
        if (end < start) return error.InvalidGlyph;
        return source.glyf.sub(start, end - start) orelse error.InvalidGlyph;
    }
};

// Component flags. Bits 0xE010 are reserved and ignored, as are OVERLAP_COMPOUND, USE_MY_METRICS, and ROUND_XY_TO_GRID.
const arg_1_and_2_are_words: u16 = 0x0001;
const args_are_xy_values: u16 = 0x0002;
const we_have_a_scale: u16 = 0x0008;
const more_components: u16 = 0x0020;
const we_have_an_x_and_y_scale: u16 = 0x0040;
const we_have_a_two_by_two: u16 = 0x0080;
const we_have_instructions: u16 = 0x0100;
const scaled_component_offset: u16 = 0x0800;
const unscaled_component_offset: u16 = 0x1000;

// Simple-glyph flags. Bit 7 is reserved and ignored, as is OVERLAP_SIMPLE.
const on_curve_point: u8 = 0x01;
const x_short_vector: u8 = 0x02;
const y_short_vector: u8 = 0x04;
const repeat_flag: u8 = 0x08;
const x_is_same_or_positive: u8 = 0x10;
const y_is_same_or_positive: u8 = 0x20;

/// The 2 × 2 component matrix: x′ = xscale·x + scale10·y and y′ = scale01·x + yscale·y.
const Matrix = struct {
    xscale: f64 = 1,
    scale01: f64 = 0,
    scale10: f64 = 0,
    yscale: f64 = 1,

    fn apply(m: Matrix, p: Point) Point {
        return .{ .x = m.xscale * p.x + m.scale10 * p.y, .y = m.scale01 * p.x + m.yscale * p.y };
    }
};

/// How a child's points are placed once they are incorporated.
const Placement = struct {
    flags: u16,
    /// Signed offsets with `ARGS_ARE_XY_VALUES`, or unsigned point numbers without it.
    arg1: i32,
    arg2: i32,
    matrix: Matrix,
    /// The index of the child's first point among all incorporated points.
    child_start: u32,
    /// Whether this is the first component record of its composite.
    first: bool,
};

/// One composite on the active chain.
const Frame = struct {
    glyph: u16,
    data: Reader,
    /// The offset of the next component record.
    cursor: u64,
    /// The index of the composite's first point among all incorporated points.
    first_point: u32,
    more: bool,
    instructions: bool,
    records: u32,
    /// The placement of the composite child that is being decoded.
    pending: Placement,
};

/// The growing outline. Every capacity stays at most `max_points` while the points budget holds.
const Builder = struct {
    gpa: Allocator,
    limits: Limits,
    points: std.ArrayList(Point) = .empty,
    on_curve: std.ArrayList(bool) = .empty,
    contour_ends: std.ArrayList(u32) = .empty,

    fn deinit(b: *Builder) void {
        b.points.deinit(b.gpa);
        b.on_curve.deinit(b.gpa);
        b.contour_ends.deinit(b.gpa);
    }

    /// The doubled capacity, capped at `max_points` but never below `needed`.
    fn grown(b: *const Builder, capacity: usize, needed: usize) usize {
        return @max(needed, @min(b.limits.max_points, @max(2 * capacity, 16)));
    }

    fn reserve(b: *Builder, points: usize, contours: usize) error{OutOfMemory}!void {
        const needed_points = b.points.items.len + points;
        if (needed_points > b.points.capacity) {
            const capacity = b.grown(b.points.capacity, needed_points);
            try b.points.ensureTotalCapacityPrecise(b.gpa, capacity);
            try b.on_curve.ensureTotalCapacityPrecise(b.gpa, capacity);
        }
        const needed_contours = b.contour_ends.items.len + contours;
        if (needed_contours > b.contour_ends.capacity) {
            try b.contour_ends.ensureTotalCapacityPrecise(b.gpa, b.grown(b.contour_ends.capacity, needed_contours));
        }
    }

    fn finish(b: *Builder, depth: u8, top_level_components: u32) error{OutOfMemory}!TrueTypeGlyph {
        const points = try b.points.toOwnedSlice(b.gpa);
        errdefer b.gpa.free(points);
        const on_curve = try b.on_curve.toOwnedSlice(b.gpa);
        errdefer b.gpa.free(on_curve);
        const contour_ends = try b.contour_ends.toOwnedSlice(b.gpa);
        return .{ .points = points, .on_curve = on_curve, .contour_ends = contour_ends, .depth = depth, .top_level_components = top_level_components };
    }
};

/// Decodes `glyph`. The checks run in order: `GlyphOutOfRange`, then `NotTrueType`, then a zero-length glyph is empty.
pub fn decode(source: Source, gpa: Allocator, glyph: u16, limits: Limits) OutlineError!TrueTypeGlyph {
    if (builtin.is_test) work = 0;
    if (glyph >= source.num_glyphs) return error.GlyphOutOfRange;
    const loca = source.loca orelse return error.NotTrueType;
    const data = try source.glyphData(loca, glyph);
    var b: Builder = .{ .gpa = gpa, .limits = limits };
    defer b.deinit();
    if (!isComposite(data)) {
        try appendSimple(&b, data);
        return b.finish(0, 0);
    }

    var frames: [max_composite_depth]Frame = undefined;
    frames[0] = startFrame(glyph, data, 0);
    var level: usize = 1;
    var depth: u8 = 1;
    var components: u64 = 0;
    while (true) {
        const top = &frames[level - 1];
        if (!top.more) {
            if (top.instructions) try skipInstructions(top.data, top.cursor);
            level -= 1;
            if (level == 0) break;
            try place(&b, frames[level - 1].pending, frames[level - 1].first_point);
            continue;
        }

        // The record layout follows the specification's pseudo-code.
        const at = top.cursor;
        const flags = top.data.u16At(at) orelse return error.InvalidGlyph;
        const child = top.data.u16At(at + 2) orelse return error.InvalidGlyph;
        const words = flags & arg_1_and_2_are_words != 0;
        const transform_len: u64 = if (flags & we_have_a_scale != 0) 2 else if (flags & we_have_an_x_and_y_scale != 0) 4 else if (flags & we_have_a_two_by_two != 0) 8 else 0;
        const args_len: u64 = if (words) 4 else 2;
        if (!top.data.fits(at, 4 + args_len + transform_len)) return error.InvalidGlyph;
        const transforms = @popCount(flags & (we_have_a_scale | we_have_an_x_and_y_scale | we_have_a_two_by_two));
        if (transforms > 1) return error.InvalidGlyph;
        if (child >= source.num_glyphs) return error.InvalidGlyph;
        components += 1;
        if (components > limits.max_components) return error.OutlineTooLarge;
        countWork();

        const xy = flags & args_are_xy_values != 0;
        var placement: Placement = .{
            .flags = flags,
            .arg1 = undefined,
            .arg2 = undefined,
            .matrix = .{},
            .child_start = @intCast(b.points.items.len),
            .first = top.records == 0,
        };
        if (words) {
            placement.arg1 = if (xy) top.data.i16At(at + 4).? else top.data.u16At(at + 4).?;
            placement.arg2 = if (xy) top.data.i16At(at + 6).? else top.data.u16At(at + 6).?;
        } else {
            placement.arg1 = if (xy) @as(i8, @bitCast(top.data.u8At(at + 4).?)) else top.data.u8At(at + 4).?;
            placement.arg2 = if (xy) @as(i8, @bitCast(top.data.u8At(at + 5).?)) else top.data.u8At(at + 5).?;
        }
        const t = at + 4 + args_len;
        switch (transform_len) {
            2 => {
                const scale = f2dot14(top.data, t);
                placement.matrix = .{ .xscale = scale, .yscale = scale };
            },
            4 => placement.matrix = .{ .xscale = f2dot14(top.data, t), .yscale = f2dot14(top.data, t + 2) },
            8 => placement.matrix = .{
                .xscale = f2dot14(top.data, t),
                .scale01 = f2dot14(top.data, t + 2),
                .scale10 = f2dot14(top.data, t + 4),
                .yscale = f2dot14(top.data, t + 6),
            },
            else => {},
        }
        top.cursor = at + 4 + args_len + transform_len;
        top.more = flags & more_components != 0;
        if (flags & we_have_instructions != 0) top.instructions = true;
        top.records += 1;

        for (frames[0..level]) |frame| if (frame.glyph == child) return error.CompositeCycle;
        const child_data = try source.glyphData(loca, child);
        if (isComposite(child_data)) {
            // The top-level composite is level 1, so the child's level is `level + 1`.
            if (level + 1 > max_composite_depth) return error.CompositeTooDeep;
            top.pending = placement;
            frames[level] = startFrame(child, child_data, placement.child_start);
            level += 1;
            depth = @max(depth, @as(u8, @intCast(level)));
        } else {
            try appendSimple(&b, child_data);
            try place(&b, placement, top.first_point);
        }
    }
    return b.finish(depth, frames[0].records);
}

fn isComposite(data: Reader) bool {
    const contours = data.i16At(0) orelse return false;
    return data.len() >= 10 and contours < 0;
}

fn startFrame(glyph: u16, data: Reader, first_point: u32) Frame {
    return .{
        .glyph = glyph,
        .data = data,
        .cursor = 10,
        .first_point = first_point,
        .more = true,
        .instructions = false,
        .records = 0,
        .pending = undefined,
    };
}

fn f2dot14(data: Reader, at: u64) f64 {
    return @as(f64, @floatFromInt(data.i16At(at).?)) / 16384;
}

/// Composite instructions: a uint16 length and that many bytes after the last record.
fn skipInstructions(data: Reader, at: u64) OutlineError!void {
    const length = data.u16At(at) orelse return error.InvalidGlyph;
    if (!data.fits(at + 2, length)) return error.InvalidGlyph;
}

/// The index of point number `number` among `count` points. The four numbers after them name phantom points.
fn pointIndex(number: i32, count: u64) OutlineError!u64 {
    if (number < 0) return error.InvalidGlyph;
    const index: u64 = @intCast(number);
    if (index < count) return index;
    if (index < count + 4) return error.UnsupportedPhantomPoint;
    return error.InvalidGlyph;
}

/// Applies the component matrix to the child's points, then moves them by the component offset.
fn place(b: *Builder, placement: Placement, parent_first: u32) OutlineError!void {
    const child = b.points.items[placement.child_start..];
    for (child) |*q| q.* = placement.matrix.apply(q.*);
    var offset: Point = undefined;
    if (placement.flags & args_are_xy_values != 0) {
        offset = .{ .x = @floatFromInt(placement.arg1), .y = @floatFromInt(placement.arg2) };
        // Both flags together fall back to the unscaled default.
        const scaled = placement.flags & scaled_component_offset != 0 and placement.flags & unscaled_component_offset == 0;
        if (scaled) offset = placement.matrix.apply(offset);
    } else {
        // Point matching needs points already incorporated, so it cannot place the first component.
        if (placement.first) return error.InvalidGlyph;
        const parent = b.points.items[parent_first..placement.child_start];
        const k = try pointIndex(placement.arg1, parent.len);
        const l = try pointIndex(placement.arg2, child.len);
        offset = .{ .x = parent[k].x - child[l].x, .y = parent[k].y - child[l].y };
    }
    for (child) |*q| q.* = .{ .x = q.x + offset.x, .y = q.y + offset.y };
}

/// One packed flag entry and its logical count.
const FlagRun = struct { flag: u8, count: u32 };

/// Reads the flag entry at `at.*`, with its repeat count when `REPEAT_FLAG` is set.
fn nextFlagRun(data: Reader, at: *u64) OutlineError!FlagRun {
    const flag = data.u8At(at.*) orelse return error.InvalidGlyph;
    at.* += 1;
    var count: u32 = 1;
    if (flag & repeat_flag != 0) {
        count += data.u8At(at.*) orelse return error.InvalidGlyph;
        at.* += 1;
    }
    return .{ .flag = flag, .count = count };
}

/// The byte length of one coordinate.
fn coordinateLength(flag: u8, short: u8, same_or_positive: u8) u64 {
    if (flag & short != 0) return 1;
    if (flag & same_or_positive != 0) return 0;
    return 2;
}

/// Reads one coordinate delta at `at.*`.
fn coordinate(data: Reader, at: *u64, flag: u8, short: u8, same_or_positive: u8) OutlineError!i64 {
    if (flag & short != 0) {
        const magnitude: i64 = data.u8At(at.*) orelse return error.InvalidGlyph;
        at.* += 1;
        return if (flag & same_or_positive != 0) magnitude else -magnitude;
    }
    if (flag & same_or_positive != 0) return 0;
    const delta = data.i16At(at.*) orelse return error.InvalidGlyph;
    at.* += 2;
    return delta;
}

/// Appends the points and contours of a simple or empty glyph. Bytes after the y array are ignored.
fn appendSimple(b: *Builder, data: Reader) OutlineError!void {
    countWork();
    if (data.len() == 0) return;
    if (data.len() < 10) return error.InvalidGlyph;
    const contours: u64 = @intCast(data.i16At(0).?);
    if (contours == 0) return;

    // The last end point gives the point count, which is checked against the budget before any point is decoded.
    const last = data.u16At(10 + 2 * (contours - 1)) orelse return error.InvalidGlyph;
    const point_count: u32 = @as(u32, last) + 1;
    if (b.points.items.len + @as(u64, point_count) > b.limits.max_points) return error.OutlineTooLarge;
    var previous: i32 = -1;
    var i: u64 = 0;
    while (i < contours) : (i += 1) {
        const end = data.u16At(10 + 2 * i).?;
        if (end <= previous) return error.InvalidGlyph;
        previous = end;
    }
    const instructions_at = 10 + 2 * contours;
    const instruction_length = data.u16At(instructions_at) orelse return error.InvalidGlyph;
    const flags_at = instructions_at + 2 + instruction_length;
    if (!data.fits(instructions_at + 2, instruction_length)) return error.InvalidGlyph;

    // The first pass expands exactly `point_count` logical flags and sizes the coordinate arrays.
    var at = flags_at;
    var expanded: u32 = 0;
    var x_length: u64 = 0;
    var y_length: u64 = 0;
    while (expanded < point_count) {
        const run = try nextFlagRun(data, &at);
        if (run.count > point_count - expanded) return error.InvalidGlyph;
        expanded += run.count;
        x_length += run.count * coordinateLength(run.flag, x_short_vector, x_is_same_or_positive);
        y_length += run.count * coordinateLength(run.flag, y_short_vector, y_is_same_or_positive);
    }
    const x_at = at;
    const y_at = x_at + x_length;
    if (!data.fits(x_at, x_length + y_length)) return error.InvalidGlyph;

    // The second pass decodes the points. Absolute coordinates are exact i64 prefix sums from (0, 0).
    try b.reserve(point_count, contours);
    const first: u32 = @intCast(b.points.items.len);
    i = 0;
    while (i < contours) : (i += 1) b.contour_ends.appendAssumeCapacity(first + data.u16At(10 + 2 * i).?);
    at = flags_at;
    var x_cursor = x_at;
    var y_cursor = y_at;
    var x: i64 = 0;
    var y: i64 = 0;
    var decoded: u32 = 0;
    while (decoded < point_count) {
        const run = try nextFlagRun(data, &at);
        if (run.count > point_count - decoded) return error.InvalidGlyph;
        for (0..run.count) |_| {
            x += try coordinate(data, &x_cursor, run.flag, x_short_vector, x_is_same_or_positive);
            y += try coordinate(data, &y_cursor, run.flag, y_short_vector, y_is_same_or_positive);
            b.points.appendAssumeCapacity(.{ .x = @floatFromInt(x), .y = @floatFromInt(y) });
            b.on_curve.appendAssumeCapacity(run.flag & on_curve_point != 0);
            countWork();
        }
        decoded += run.count;
    }
}
