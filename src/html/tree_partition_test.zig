//! FP-0100 contract case 12: the tree construction partition harness.
//!
//! The harness parses each input once as one chunk, which gives the reference record: the outcome sequence without
//! `need_input`, the errors with their positions, the document mode, and the dump, as `tree_test.parseChunks` writes it.
//! The reference must equal the case's frozen values. The harness then parses the input under each partition of its set,
//! with the visiting order of `partition_test.firstMismatch`, and every partition must give a byte-identical record.
//! On a mismatch, it reports the case, the input, the failing partition with the fewest chunks, both records, and the
//! 1-minimal input that `lab.ddmin` finds under the predicate "some partition of the candidate mismatches".

const std = @import("std");
const lab = @import("../lab.zig");
const dump = @import("dump.zig");
const html = @import("root.zig");
const partition_test = @import("partition_test.zig");
const cases = @import("tree_test.zig");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Set = partition_test.Set;

/// Holds when the record of `input` under a partition differs from the reference record.
const RecordMismatch = struct {
    gpa: Allocator,
    input: []const u16,
    scripting: html.ScriptingMode,
    reference: []const u8,

    pub fn mismatches(p: *const RecordMismatch, boundaries: []const usize) !bool {
        var observed = try cases.parseChunks(p.gpa, p.input, boundaries, p.scripting);
        defer observed.deinit(p.gpa);
        return !std.mem.eql(u8, p.reference, observed.record);
    }
};

/// Holds when some partition of the candidate in `set` mismatches.
const SomePartitionMismatches = struct {
    gpa: Allocator,
    set: Set,
    scripting: html.ScriptingMode,

    pub fn holds(p: *const SomePartitionMismatches, candidate: []const u16) !bool {
        var reference = try cases.parseChunks(p.gpa, candidate, &.{}, p.scripting);
        defer reference.deinit(p.gpa);
        const predicate: RecordMismatch = .{ .gpa = p.gpa, .input = candidate, .scripting = p.scripting, .reference = reference.record };
        const found = try partition_test.firstMismatch(p.gpa, candidate.len, p.set, &predicate) orelse return false;
        p.gpa.free(found);
        return true;
    }
};

const Input = struct { id: []const u8, case: []const u8, units: usize, set: Set };

/// The table of case 12. Each case's scripting mode is its own.
const inputs = [_]Input{
    .{ .id = "Q1", .case = "B13", .units = 14, .set = .all },
    .{ .id = "Q2", .case = "B12", .units = 12, .set = .all },
    .{ .id = "Q3", .case = "B1", .units = 4, .set = .all },
    .{ .id = "Q4", .case = "B11", .units = 10, .set = .all },
    .{ .id = "Q5", .case = "A7", .units = 12, .set = .all },
    .{ .id = "Q6", .case = "B2", .units = 16, .set = .up_to_three },
    .{ .id = "Q7", .case = "S1", .units = 23, .set = .up_to_three },
    .{ .id = "Q8", .case = "A10", .units = 42, .set = .up_to_three },
    .{ .id = "Q9", .case = "W3", .units = 197, .set = .up_to_three },
    .{ .id = "Q10", .case = "A2", .units = 17, .set = .up_to_three },
    .{ .id = "Q11", .case = "B30", .units = 16, .set = .up_to_three },
    .{ .id = "Q12", .case = "B10", .units = 58, .set = .up_to_three },
    .{ .id = "Q13", .case = "B32", .units = 4, .set = .all },
};

/// Writes the mismatch report: the case, the input, the partition's chunks as half-open ranges, both records,
/// and the minimal input.
fn report(w: *std.Io.Writer, input: Input, units: []const u16, boundaries: []const usize, reference: []const u8, observed: []const u8, minimal: []const u16) !void {
    try w.print("FP-0100 case 12 partition mismatch on input {s} ({s}): ", .{ input.id, input.case });
    try dump.writeString(w, units);
    try w.writeAll("\npartition:");
    var start: usize = 0;
    for (0..boundaries.len + 1) |index| {
        const end = if (index < boundaries.len) boundaries[index] else units.len;
        try w.print(" [{d},{d})", .{ start, end });
        start = end;
    }
    try w.print("\nreference record:\n{s}partition record:\n{s}1-minimal input: ", .{ reference, observed });
    try dump.writeString(w, minimal);
    try w.writeByte('\n');
}

/// Checks the input's length, its frozen record, and every partition in its set. Prints each failure and returns false.
fn checkInput(input: Input) !bool {
    const gpa = testing.allocator;
    const case = cases.find(input.case);
    const units = try cases.units(gpa, case.input);
    defer gpa.free(units);
    var passed = true;
    if (units.len != input.units) {
        std.debug.print("FP-0100 case 12, input {s}: the case lists {d} code units, and the input has {d}\n", .{ input.id, input.units, units.len });
        passed = false;
    }
    const expected = try cases.expectedRecord(gpa, case);
    defer gpa.free(expected);
    var reference = try cases.parseChunks(gpa, units, &.{}, case.scripting);
    defer reference.deinit(gpa);
    if (!std.mem.eql(u8, expected, reference.record)) {
        std.debug.print("FP-0100 case 12, input {s} ({s}):\nexpected:\n{s}reference:\n{s}", .{ input.id, input.case, expected, reference.record });
        return false;
    }
    const partitions: RecordMismatch = .{ .gpa = gpa, .input = units, .scripting = case.scripting, .reference = reference.record };
    const boundaries = try partition_test.firstMismatch(gpa, units.len, input.set, &partitions) orelse return passed;
    defer gpa.free(boundaries);
    var observed = try cases.parseChunks(gpa, units, boundaries, case.scripting);
    defer observed.deinit(gpa);
    const minimizer: SomePartitionMismatches = .{ .gpa = gpa, .set = input.set, .scripting = case.scripting };
    const minimal = try lab.ddmin(u16, gpa, units, &minimizer);
    defer gpa.free(minimal);
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try report(&out.writer, input, units, boundaries, reference.record, observed.record, minimal);
    std.debug.print("{s}", .{out.written()});
    return false;
}

fn checkSet(set: Set) !void {
    var failed = false;
    for (inputs) |input| {
        if (input.set != set) continue;
        if (!try checkInput(input)) failed = true;
    }
    try testing.expect(!failed);
}

test "FP-0100 case 12: set P compares every composition of each input into nonempty chunks with the whole input" {
    try checkSet(.all);
}

test "FP-0100 case 12: set B compares every partition of each input into one, two, or three chunks with the whole input" {
    try checkSet(.up_to_three);
}
