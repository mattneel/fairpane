//! Extended grapheme cluster boundaries over UTF-16 code units: UAX #29 revision 49, rules GB1 to GB999.
//!
//! Code points follow `web_string.CodePointIterator`: a high surrogate followed by a low surrogate is one code point,
//! and every other surrogate is its own code point. Boundaries are code-unit indexes, so a boundary never falls between
//! the two units of a surrogate pair. Each code point's properties come from `unicode.lookup`.

const builtin = @import("builtin");
const unicode = @import("../unicode/properties.zig");
const web_string = @import("../web_string.zig");

const Gcb = unicode.GraphemeClusterBreak;
const Incb = unicode.IndicConjunctBreak;
const CodeUnitIndex = web_string.CodeUnitIndex;

/// One decoded code point: the properties that the rules read, and its length in code units.
const CodePoint = struct {
    gcb: Gcb,
    incb: Incb,
    ext_pict: bool,
    len: usize,
};

/// Iterates the extended grapheme cluster boundaries of one string in increasing order.
/// The state has constant size: the previous code point's Grapheme_Cluster_Break value and four facts about the
/// code points that end at it. Each code point is decoded once, and the code unit after a lone high surrogate is read
/// at most twice, so the work is linear in the code-unit length.
pub const GraphemeBoundaries = struct {
    units: []const u16,
    /// The index after the last code point decoded.
    index: usize = 0,
    phase: enum { start, inside, done } = .start,
    /// The Grapheme_Cluster_Break value of the code point that ends at `index`.
    previous: Gcb = .XX,
    /// GB9c: `InCB=Linker InCB=Extend*` ends at `index`.
    linker: bool = false,
    /// GB11: `ExtPict EX*` ends at `index`.
    pictographic: bool = false,
    /// GB11: a ZWJ that follows `ExtPict EX*` ends at `index`.
    pictographic_zwj: bool = false,
    /// GB12 and GB13: an odd number of consecutive RI code points ends at `index`.
    odd_regional_indicators: bool = false,
    /// The number of code units read, which only test builds count.
    units_read: if (builtin.is_test) usize else void = if (builtin.is_test) 0 else {},

    pub fn init(string: web_string.View) GraphemeBoundaries {
        return .{ .units = string.units };
    }

    /// The next extended grapheme cluster boundary, or null after the last one.
    pub fn next(self: *GraphemeBoundaries) ?CodeUnitIndex {
        switch (self.phase) {
            .done => return null,
            .start => {
                // GB1 and GB2 apply only to nonempty text.
                if (self.units.len == 0) {
                    self.phase = .done;
                    return null;
                }
                self.consume(self.decode());
                self.phase = .inside;
                return boundary(0);
            },
            .inside => {},
        }
        while (self.index < self.units.len) {
            const start = self.index;
            const code_point = self.decode();
            const joined = self.joins(code_point);
            self.consume(code_point);
            if (!joined) return boundary(start);
        }
        // GB2.
        self.phase = .done;
        return boundary(self.units.len);
    }

    fn boundary(index: usize) CodeUnitIndex {
        return @fromBackingInt(index);
    }

    /// Reads one code unit. Every read of the string goes through this accessor, so test builds count the work.
    fn unitAt(self: *GraphemeBoundaries, index: usize) u16 {
        if (builtin.is_test) self.units_read += 1;
        return self.units[index];
    }

    /// Decodes the code point that starts at `index` without consuming it.
    fn decode(self: *GraphemeBoundaries) CodePoint {
        const first = self.unitAt(self.index);
        var code_point: u21 = first;
        var len: usize = 1;
        if (first >= 0xD800 and first <= 0xDBFF and self.index + 1 < self.units.len) {
            const second = self.unitAt(self.index + 1);
            if (second >= 0xDC00 and second <= 0xDFFF) {
                code_point = 0x10000 + ((@as(u21, first) - 0xD800) << 10) + (second - 0xDC00);
                len = 2;
            }
        }
        // A decoded code point is at most U+10FFFF.
        const properties = unicode.lookup(code_point) catch unreachable;
        return .{ .gcb = properties.gcb, .incb = properties.incb, .ext_pict = properties.ext_pict, .len = len };
    }

    /// Whether the first matching rule, in the order of UAX #29 section 3.1.1, joins `next_code_point` to the code point before it.
    fn joins(self: *const GraphemeBoundaries, next_code_point: CodePoint) bool {
        const p = self.previous;
        const n = next_code_point.gcb;
        if (p == .CR and n == .LF) return true; // GB3
        if (p == .CN or p == .CR or p == .LF) return false; // GB4
        if (n == .CN or n == .CR or n == .LF) return false; // GB5
        if (p == .L and (n == .L or n == .V or n == .LV or n == .LVT)) return true; // GB6
        if ((p == .LV or p == .V) and (n == .V or n == .T)) return true; // GB7
        if ((p == .LVT or p == .T) and n == .T) return true; // GB8
        if (n == .EX or n == .ZWJ) return true; // GB9
        if (n == .SM) return true; // GB9a
        if (p == .PP) return true; // GB9b
        if (self.linker and next_code_point.incb == .Consonant) return true; // GB9c
        if (self.pictographic_zwj and next_code_point.ext_pict) return true; // GB11
        if (self.odd_regional_indicators and n == .RI) return true; // GB12 and GB13
        return false; // GB999
    }

    /// Makes `code_point` the previous code point and updates the facts that end at it.
    fn consume(self: *GraphemeBoundaries, code_point: CodePoint) void {
        self.pictographic_zwj = code_point.gcb == .ZWJ and self.pictographic;
        self.pictographic = code_point.ext_pict or (self.pictographic and code_point.gcb == .EX);
        self.linker = code_point.incb == .Linker or (self.linker and code_point.incb == .Extend);
        self.odd_regional_indicators = code_point.gcb == .RI and !self.odd_regional_indicators;
        self.previous = code_point.gcb;
        self.index += code_point.len;
    }
};
