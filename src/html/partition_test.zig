//! FP-0008 contract cases 13 and 14 and FP-0064 contract case 13: the partition harness.
//!
//! The harness tokenizes each input once as one chunk, which gives the reference dump with spans and errors,
//! and then under each partition of a set, as `tokenizer_test.tokenizeChunks` describes. Each input starts as its
//! `Setup` describes, and the content driver runs after every step. Every partition must produce a byte-identical dump.
//! On a mismatch, the harness reports the case, the input, the failing partition with the fewest chunks, with ties going
//! to the lexicographically lowest list of boundary offsets, both dumps, and the 1-minimal input that `lab.ddmin` finds
//! under the predicate "some partition of the candidate mismatches".

const std = @import("std");
const lab = @import("../lab.zig");
const dump = @import("dump.zig");
const tokenizer = @import("tokenizer.zig");
const states = @import("states.zig");
const cases = @import("tokenizer_test.zig");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Setup = cases.Setup;

pub const Set = enum {
    /// Every composition into nonempty chunks: 2^(n-1) partitions of n units.
    all,
    /// Every partition into one, two, or three nonempty chunks.
    up_to_three,
};

/// Advances `chosen`, a strictly increasing list of values from 1 to `max`, to the next such list in lexicographic order.
/// Returns false after the last list.
fn nextCombination(chosen: []usize, max: usize) bool {
    const k = chosen.len;
    var index = k;
    while (index > 0) {
        index -= 1;
        if (chosen[index] < max - (k - 1 - index)) {
            chosen[index] += 1;
            for (index + 1..k) |later| chosen[later] = chosen[later - 1] + 1;
            return true;
        }
    }
    return false;
}

/// Visits the partitions of `n` units in `set` by chunk count and then by the lexicographic order of their boundary lists,
/// and returns the boundaries of the first one for which `predicate.mismatches(boundaries)` holds, or null.
/// The caller frees the result with `gpa`.
pub fn firstMismatch(gpa: Allocator, n: usize, set: Set, predicate: anytype) !?[]usize {
    if (n == 0) return null;
    const most = switch (set) {
        .all => n - 1,
        .up_to_three => @min(2, n - 1),
    };
    const boundaries = try gpa.alloc(usize, most);
    defer gpa.free(boundaries);
    for (0..most + 1) |count| {
        const chosen = boundaries[0..count];
        for (chosen, 1..) |*boundary, value| boundary.* = value;
        while (true) {
            if (try predicate.mismatches(chosen)) return try gpa.dupe(usize, chosen);
            if (!nextCombination(chosen, n - 1)) break;
        }
    }
    return null;
}

/// Holds when the dump of `input` under a partition differs from the reference dump.
const DumpMismatch = struct {
    gpa: Allocator,
    input: []const u16,
    setup: Setup,
    reference: []const u8,

    pub fn mismatches(p: *const DumpMismatch, boundaries: []const usize) !bool {
        const observed = try cases.tokenizeChunks(p.gpa, p.input, boundaries, dump.full, p.setup);
        defer p.gpa.free(observed);
        return !std.mem.eql(u8, p.reference, observed);
    }
};

/// Holds when some partition of the candidate in `set` mismatches.
const SomePartitionMismatches = struct {
    gpa: Allocator,
    set: Set,
    setup: Setup,

    pub fn holds(p: *const SomePartitionMismatches, candidate: []const u16) !bool {
        const reference = try cases.tokenizeChunks(p.gpa, candidate, &.{}, dump.full, p.setup);
        defer p.gpa.free(reference);
        const predicate: DumpMismatch = .{ .gpa = p.gpa, .input = candidate, .setup = p.setup, .reference = reference };
        const found = try firstMismatch(p.gpa, candidate.len, p.set, &predicate) orelse return false;
        p.gpa.free(found);
        return true;
    }
};

pub const Report = struct {
    /// The input, which the report borrows.
    input: []const u16,
    /// The boundaries of the failing partition.
    boundaries: []usize,
    reference: []u8,
    observed: []u8,
    minimal: []u16,

    pub fn deinit(r: *Report, gpa: Allocator) void {
        gpa.free(r.boundaries);
        gpa.free(r.reference);
        gpa.free(r.observed);
        gpa.free(r.minimal);
        r.* = undefined;
    }

    /// Writes the report: the case, the input, the partition's chunks as half-open ranges, both dumps, and the minimal input.
    pub fn write(r: *const Report, w: *std.Io.Writer, case: []const u8, id: []const u8) std.Io.Writer.Error!void {
        try w.print("{s} partition mismatch on input {s}: ", .{ case, id });
        try dump.writeString(w, r.input);
        try w.writeAll("\npartition:");
        var start: usize = 0;
        for (0..r.boundaries.len + 1) |index| {
            const end = if (index < r.boundaries.len) r.boundaries[index] else r.input.len;
            try w.print(" [{d},{d})", .{ start, end });
            start = end;
        }
        try w.print("\nreference dump:\n{s}partition dump:\n{s}1-minimal input: ", .{ r.reference, r.observed });
        try dump.writeString(w, r.minimal);
        try w.writeByte('\n');
    }
};

/// Runs the harness with injected predicates: `partitions.mismatches(boundaries)` decides which partitions mismatch,
/// and `inputs.holds(candidate)` is the minimization predicate. Returns null when no partition mismatches.
pub fn checkWith(gpa: Allocator, input: []const u16, set: Set, setup: Setup, partitions: anytype, inputs: anytype) !?Report {
    const boundaries = try firstMismatch(gpa, input.len, set, partitions) orelse return null;
    errdefer gpa.free(boundaries);
    const reference = try cases.tokenizeChunks(gpa, input, &.{}, dump.full, setup);
    errdefer gpa.free(reference);
    const observed = try cases.tokenizeChunks(gpa, input, boundaries, dump.full, setup);
    errdefer gpa.free(observed);
    const minimal = try lab.ddmin(u16, gpa, input, inputs);
    return .{ .input = input, .boundaries = boundaries, .reference = reference, .observed = observed, .minimal = minimal };
}

/// Runs the harness on `input` with every partition in `set`. Returns null when every partition matches the reference dump.
pub fn check(gpa: Allocator, input: []const u16, set: Set, setup: Setup) !?Report {
    const reference = try cases.tokenizeChunks(gpa, input, &.{}, dump.full, setup);
    defer gpa.free(reference);
    const partitions: DumpMismatch = .{ .gpa = gpa, .input = input, .setup = setup, .reference = reference };
    const inputs: SomePartitionMismatches = .{ .gpa = gpa, .set = set, .setup = setup };
    return checkWith(gpa, input, set, setup, &partitions, &inputs);
}

/// One input of a partition case: its ID, its `Setup`, its notation, its expected dump, and the options of that dump.
const Input = struct {
    id: []const u8,
    setup: Setup = .{},
    notation: []const u8,
    expected: []const u8,
    options: dump.Options = dump.plain,
    units: ?usize = null,
};

/// Checks the length of `input`, its expected dump, and then every partition in `set`. Prints each mismatch, naming
/// `case`, and returns false when any check fails. A wrong length does not stop the dump and partition checks.
fn checkInput(case: []const u8, input: Input, set: Set) !bool {
    const gpa = testing.allocator;
    const units = try cases.decodeInput(gpa, input.notation);
    defer gpa.free(units);
    var passed = true;
    if (input.units) |count| {
        if (count != units.len) {
            std.debug.print("{s}, input {s}: the case lists {d} code units, and the input has {d}\n", .{ case, input.id, count, units.len });
            passed = false;
        }
    }
    const observed = try cases.tokenizeChunks(gpa, units, &.{}, input.options, input.setup);
    defer gpa.free(observed);
    if (!std.mem.eql(u8, input.expected, observed)) {
        std.debug.print("{s}, input {s}:\nexpected:\n{s}observed:\n{s}", .{ case, input.id, input.expected, observed });
        return false;
    }
    var report = try check(gpa, units, set, input.setup) orelse return passed;
    defer report.deinit(gpa);
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try report.write(&out.writer, case, input.id);
    std.debug.print("{s}", .{out.written()});
    return false;
}

/// Checks a case whose expected value is a sequence in the notation, or `=X` for the expected sequence of case X.
fn checkNotation(case: []const u8, id: []const u8, setup: Setup, notation: []const u8, expected: []const u8, set: Set, units: ?usize) !bool {
    const gpa = testing.allocator;
    const sequence = if (expected[0] == '=') cases.find(expected[1..]).expected else expected;
    const expected_dump = try cases.expectedDump(gpa, sequence);
    defer gpa.free(expected_dump);
    return checkInput(case, .{ .id = id, .setup = setup, .notation = notation, .expected = expected_dump, .units = units }, set);
}

const PCase = struct { id: []const u8, setup: Setup = .{}, input: []const u8, units: usize, expected: []const u8 };

/// FP-0008 set P. An expected value `=X` is the expected sequence of case X.
const set_p = [_]PCase{
    .{ .id = "P1", .input = "a\\r\\nb\\r\\rc\\r", .units = 8, .expected = "=N1" },
    .{ .id = "P2", .input = "\\uD800a\\uDC00\\uD83D\\uDE00\\uDBFF", .units = 6, .expected = "=N4" },
    .{ .id = "P3", .input = "\\uFDD0\\uD83F\\uDFFE\\u0001\\u007F\\u0000", .units = 6, .expected = "!noncharacter-in-input-stream@1:1 C\"\\uFDD0\" !noncharacter-in-input-stream@1:2 C\"\\uD83F\\uDFFE\" !control-character-in-input-stream@1:4 C\"\\u0001\" !control-character-in-input-stream@1:5 C\"\\u007F\" !unexpected-null-character@1:6 C\"\\u0000\" EOF" },
    .{ .id = "P4", .input = "<!DOCTYPE html>", .units = 15, .expected = "=D1" },
    .{ .id = "P5", .input = "<!--a--!>", .units = 9, .expected = "=A18" },
    .{ .id = "P6", .input = "<!-x>", .units = 5, .expected = "=M25" },
    .{ .id = "P7", .input = "&notin;&notit;", .units = 14, .expected = "C\"\\u2209\" !missing-semicolon-after-character-reference@1:11 C\"\\u00ACit;\" EOF" },
    .{ .id = "P8", .input = "<a b=\"&ampx&lt\">", .units = 16, .expected = "!missing-semicolon-after-character-reference@1:14 S\"a\"[b=\"&ampx<\"] EOF" },
    .{ .id = "P9", .input = "&#x110000;&#0;", .units = 14, .expected = "!character-reference-outside-unicode-range@1:10 C\"\\uFFFD\" !null-character-reference@1:14 C\"\\uFFFD\" EOF" },
    .{ .id = "P10", .input = "<?xml x?><?a?b>", .units = 15, .expected = "!disallowed-processing-instruction-target@1:6 M\"?xml x?\" P(\"a\",\"?b\") EOF" },
    .{ .id = "P11", .input = "<a b c=d b=e/>", .units = 14, .expected = "!duplicate-attribute@1:11 S\"a\"[b=\"\" c=\"d\"] EOF" },
    .{ .id = "P12", .input = "</a b></a/>", .units = 11, .expected = "!end-tag-with-attributes@1:6 E\"a\"[b=\"\"] !end-tag-with-trailing-solidus@1:11 E\"a\"[]/ EOF" },
    .{ .id = "P13", .input = "<a b='c", .units = 7, .expected = "=A17" },
    .{ .id = "P14", .input = "&;&#;&#x;&a;", .units = 12, .expected = "C\"&;\" !absence-of-digits-in-numeric-character-reference@1:5 C\"&#;\" !absence-of-digits-in-numeric-character-reference@1:9 C\"&#x;&a\" !unknown-named-character-reference@1:12 C\";\" EOF" },
    .{ .id = "P15", .input = "x&notin", .units = 7, .expected = "C\"x\" !missing-semicolon-after-character-reference@1:5 C\"\\u00ACin\" EOF" },
    .{ .id = "P16", .input = "&#X41;&#65", .units = 10, .expected = "C\"A\" !missing-semicolon-after-character-reference@1:11 C\"A\" EOF" },
    .{ .id = "P17", .input = "&#x80;&#xFFFE;", .units = 14, .expected = "!control-character-reference@1:6 C\"\\u20AC\" !noncharacter-character-reference@1:14 C\"\\uFFFE\" EOF" },
    .{ .id = "P18", .input = "&#xD800;&#13;", .units = 13, .expected = "!surrogate-character-reference@1:8 C\"\\uFFFD\" !control-character-reference@1:13 C\"\\u000D\" EOF" },
    .{ .id = "P19", .input = "<!--<!-- -->", .units = 12, .expected = "!nested-comment@1:9 M\"<!-- \" EOF" },
    .{ .id = "P20", .input = "<A B=C>&lt", .units = 10, .expected = "S\"a\"[b=\"C\"] !missing-semicolon-after-character-reference@1:10 C\"<\" EOF" },
    .{ .id = "P21", .input = "<a\\rb='\\r\\n'>\\r", .units = 11, .expected = "=N6" },
    .{ .id = "P22", .input = "<!DOCTYP", .units = 8, .expected = "=M23" },
};

/// The inputs of FP-0008 set B other than the earlier cases that it names.
const set_b = [_]cases.Case{
    .{ .id = "B1", .input = "<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01//EN\" \"http://www.w3.org/TR/html4/strict.dtd\">", .expected = "D(\"html\",\"-//W3C//DTD HTML 4.01//EN\",\"http://www.w3.org/TR/html4/strict.dtd\",off) EOF" },
    .{ .id = "B2", .input = "&NotEqualTilde;&CounterClockwiseContourIntegral;&CounterClockwiseContourIntegralx", .expected = "C\"\\u2242\\u0338\\u2233&CounterClockwiseContourIntegralx\" EOF" },
    .{ .id = "B3", .input = "<p title=\"a&amp;b\" data-x=1 hidden>text&copy 2026</p>", .expected = "S\"p\"[title=\"a&b\" data-x=\"1\" hidden=\"\"] C\"text\" !missing-semicolon-after-character-reference@1:44 C\"\\u00A9 2026\" E\"p\"[] EOF" },
    .{ .id = "B4", .input = "<!--a--><!--b--!><!----><?pi d?><x y='z'/>", .expected = "M\"a\" !incorrectly-closed-comment@1:17 M\"b\" M\"\" P(\"pi\",\"d\") S\"x\"[y=\"z\"]/ EOF" },
};

test "FP-0008 case 13: set P compares every composition of each input into nonempty chunks with the whole input" {
    var failed = false;
    for (set_p) |case| {
        if (!try checkNotation("FP-0008 case 13", case.id, case.setup, case.input, case.expected, .all, case.units)) failed = true;
    }
    try testing.expect(!failed);
}

test "FP-0008 case 13: set B compares every partition of each input into one, two, or three chunks with the whole input" {
    var failed = false;
    for ([_][]const u8{ "D7", "D20", "T13", "R3", "R5", "N2", "N3" }) |id| {
        const case = cases.find(id);
        if (!try checkNotation("FP-0008 case 13", id, case.setup, case.input, case.expected, .up_to_three, null)) failed = true;
    }
    const s1: Input = .{ .id = "S1", .notation = cases.s1_input, .expected = cases.s1_dump, .options = dump.full, .units = 51 };
    if (!try checkInput("FP-0008 case 13", s1, .up_to_three)) failed = true;
    for (set_b) |case| {
        if (!try checkNotation("FP-0008 case 13", case.id, case.setup, case.input, case.expected, .up_to_three, null)) failed = true;
    }
    try testing.expect(!failed);
}

/// FP-0064 set P, other than the case 12 inputs. An expected value `=X` is the expected sequence of case X.
const content_set_p = [_]PCase{
    .{ .id = "Q1", .input = "<xmp>a</xmp>b", .units = 13, .expected = "S\"xmp\"[] C\"a\" E\"xmp\"[] C\"b\" EOF" },
    .{ .id = "Q2", .input = "<xmp></xmpa>", .units = 12, .expected = "S\"xmp\"[] C\"</xmpa>\" EOF" },
    .{ .id = "Q3", .input = "<xmp></XMP\\r\\n>", .units = 13, .expected = "S\"xmp\"[] E\"xmp\"[] EOF" },
    .{ .id = "Q4", .setup = cases.start_rcdata, .input = "&lt</a>\\r\\n", .units = 9, .expected = "!missing-semicolon-after-character-reference@1:3 C\"<</a>\\u000A\" EOF" },
    .{ .id = "Q5", .setup = cases.start_script, .input = "<!--<script>-->", .units = 15, .expected = "C\"<!--<script>-->\" EOF" },
    .{ .id = "Q6", .setup = cases.start_script, .input = "<!-x<!--\\0-", .units = 10, .expected = "C\"<!-x<!--\" !unexpected-null-character@1:9 C\"\\uFFFD-\" !eof-in-script-html-comment-like-text@1:11 EOF" },
    .{ .id = "Q7", .setup = cases.start_script, .input = "<!--<SCRIPT>-\\0", .units = 14, .expected = "C\"<!--<SCRIPT>-\" !unexpected-null-character@1:14 C\"\\uFFFD\" !eof-in-script-html-comment-like-text@1:15 EOF" },
    .{ .id = "Q8", .setup = cases.start_script, .input = "<!--</script>", .units = 13, .expected = "C\"<!--</script>\" !eof-in-script-html-comment-like-text@1:14 EOF" },
    .{ .id = "Q9", .setup = cases.foreign, .input = "<![CDATA[a]]]>", .units = 14, .expected = "C\"a]\" EOF" },
    .{ .id = "Q10", .setup = cases.foreign, .input = "<![CDATA[]\\0]", .units = 12, .expected = "C\"]\\u0000]\" !eof-in-cdata@1:13 EOF" },
    // Contract amendment 1 sets the Units value of Q11 to 14, the length of its input.
    .{ .id = "Q11", .setup = cases.foreign, .input = "<![CDATA[\\uD83D\\uDE00]]>", .units = 14, .expected = "C\"\\uD83D\\uDE00\" EOF" },
    .{ .id = "Q12", .setup = cases.foreign, .input = "<![CDATA[x]]>", .units = 13, .expected = "C\"x\" EOF" },
    .{ .id = "Q13", .input = "<![CDATA[x]]>", .units = 13, .expected = "=A5" },
    .{ .id = "Q14", .setup = cases.start_plaintext, .input = "a\\r</plaintext>", .units = 14, .expected = "C\"a\\u000A</plaintext>\" EOF" },
    .{ .id = "Q15", .setup = cases.start_rawtext, .input = "\\uD800</\\uDC00", .units = 4, .expected = "!surrogate-in-input-stream@1:1 C\"\\uD800\" !surrogate-in-input-stream@1:4 C\"</\\uDC00\" EOF" },
    .{ .id = "Q16", .setup = cases.start_script, .input = "<!--<script></s", .units = 15, .expected = "C\"<!--<script></s\" !eof-in-script-html-comment-like-text@1:16 EOF" },
};

/// The case 12 inputs of FP-0064 set P, whose expected value is the full dump of case 12.
fn sourceInput(case: cases.SourceCase) Input {
    return .{ .id = case.id, .setup = case.setup, .notation = case.input, .expected = case.dump, .options = dump.full, .units = case.units };
}

test "FP-0064 case 13: set P compares every composition of each input into nonempty chunks with the whole input" {
    var failed = false;
    for (content_set_p) |case| {
        if (!try checkNotation("FP-0064 case 13", case.id, case.setup, case.input, case.expected, .all, case.units)) failed = true;
    }
    for (cases.source_cases) |case| {
        if (!try checkInput("FP-0064 case 13", sourceInput(case), .all)) failed = true;
    }
    try testing.expect(!failed);
}

test "FP-0064 case 13: each set P input as one chunk executes every one of the 30 new states" {
    const gpa = testing.allocator;
    @memset(&tokenizer.coverage, 0);
    for (content_set_p) |case| {
        const input = try cases.decodeInput(gpa, case.input);
        defer gpa.free(input);
        gpa.free(try cases.tokenizeChunks(gpa, input, &.{}, dump.full, case.setup));
    }
    for (cases.source_cases) |case| {
        const input = try cases.decodeInput(gpa, case.input);
        defer gpa.free(input);
        gpa.free(try cases.tokenizeChunks(gpa, input, &.{}, dump.full, case.setup));
    }
    // Sum the branch counters of each state.
    var executed: std.EnumArray(states.State, u64) = .initFill(0);
    for (tokenizer.coverage, 0..) |count, index| executed.getPtr(states.branchAt(index).state).* += count;
    var missing: usize = 0;
    for (std.enums.values(states.State)) |state| {
        if (!cases.addedByContentStates(state) or executed.get(state) != 0) continue;
        std.debug.print("FP-0064 case 13: no set P input executes the {s}\n", .{states.title(state)});
        missing += 1;
    }
    try testing.expectEqual(@as(usize, 0), missing);
}

test "FP-0064 case 13: set B compares every partition of each input into one, two, or three chunks with the whole input" {
    var failed = false;
    const ids = [_][]const u8{ "RC1", "RC8", "RC11", "RW1", "RW3", "SD3", "SD11", "SE1", "SE4", "SE5", "DE1", "DE5", "DE7", "DE8", "PT1", "CD1", "CD2", "CD5", "L1", "L6" };
    for (ids) |id| {
        const case = cases.find(id);
        if (!try checkNotation("FP-0064 case 13", id, case.setup, case.input, case.expected, .up_to_three, null)) failed = true;
    }
    try testing.expect(!failed);
}

/// Holds when the candidate contains U+000D followed by U+000A.
const ContainsCrLf = struct {
    pub fn holds(_: *const ContainsCrLf, candidate: []const u16) !bool {
        return std.mem.indexOf(u16, candidate, &.{ '\r', '\n' }) != null;
    }
};

/// Holds for a partition with a boundary at offset 4.
const BoundaryAtFour = struct {
    pub fn mismatches(_: *const BoundaryAtFour, boundaries: []const usize) !bool {
        return std.mem.indexOfScalar(usize, boundaries, 4) != null;
    }
};

test "FP-0008 case 14: the mismatch report names the 1-minimal input and the partition with the fewest chunks" {
    const gpa = testing.allocator;
    const input = try cases.decodeInput(gpa, "a\\r\\nb\\r\\n");
    defer gpa.free(input);
    try testing.expectEqual(@as(usize, 6), input.len);
    var report = (try checkWith(gpa, input, .all, .{}, &BoundaryAtFour{}, &ContainsCrLf{})).?;
    defer report.deinit(gpa);
    try testing.expectEqualSlices(u16, &.{ '\r', '\n' }, report.minimal);
    try testing.expectEqualSlices(usize, &.{4}, report.boundaries);
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try report.write(&out.writer, "FP-0008 case 14", "injected");
    try testing.expect(std.mem.indexOf(u8, out.written(), "\npartition: [0,4) [4,6)\n") != null);
    try testing.expect(std.mem.indexOf(u8, out.written(), "\n1-minimal input: \"\\u000D\\u000A\"\n") != null);
    // The real harness finds no mismatch for the same input.
    if (try check(gpa, input, .all, .{})) |found| {
        var unexpected = found;
        defer unexpected.deinit(gpa);
        try unexpected.write(&out.writer, "FP-0008 case 14", "without injected predicates");
        std.debug.print("{s}", .{out.written()});
        return error.TestUnexpectedResult;
    }
    // Ties go to the lexicographically lowest boundary list: the first three-chunk partition has boundaries 1 and 2.
    const ThreeChunks = struct {
        pub fn mismatches(_: *const @This(), boundaries: []const usize) !bool {
            return boundaries.len == 2;
        }
    };
    const first = (try firstMismatch(gpa, 6, .all, &ThreeChunks{})).?;
    defer gpa.free(first);
    try testing.expectEqualSlices(usize, &.{ 1, 2 }, first);
}
