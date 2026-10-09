//! The named character references of HTML Standard §13.5.
//!
//! The table comes from the unedited `entities.json` beside this file.
//! `entities_gen.zig` generates `entities_table.zig` from it, and `zig build entities-generate` writes that file into the source tree.
//! FP-0008 contract case 3 compares the committed table with a parse of `entities.json`, so a stale table fails the tests.
//! `entities.provenance.json` records its source, digest, and license, and `entities.LICENSE` holds that license.

const generated = @import("entities_table.zig");

pub const Entity = generated.Entity;

/// Every name, sorted by its UTF-16 code units. Each name is ASCII, so each byte is one code unit.
pub const table: []const Entity = &generated.entities;

/// The length of the longest name in code units.
pub const max_name_len: usize = generated.max_name_len;

/// Finds the longest name that is a prefix of the input, one code unit at a time, without allocating.
///
/// The table entries whose names begin with the units fed so far form the range `[lo, hi)`,
/// because the table is sorted. A name equal to those units sorts first in that range.
pub const Matcher = struct {
    lo: usize = 0,
    hi: usize = table.len,
    /// The number of units fed so far.
    len: usize = 0,
    /// The index of the longest name equal to a prefix fed so far, or null.
    best: ?usize = null,

    /// Feeds the next unit and returns whether some name still begins with every unit fed.
    /// Requires that the previous call returned true.
    pub fn feed(m: *Matcher, unit: u16) bool {
        var lo = m.lo;
        // Skip the name that ends here, which sorts before every longer name with the same prefix.
        if (lo < m.hi and table[lo].name.len == m.len) lo += 1;
        const first = boundary(lo, m.hi, m.len, unit, false);
        const last = boundary(first, m.hi, m.len, unit, true);
        m.lo = first;
        m.hi = last;
        m.len += 1;
        if (first == last) return false;
        if (table[first].name.len == m.len) m.best = first;
        return true;
    }

    /// Returns the first index in `[lo, hi)` whose unit at `position` is at least `unit`, or above `unit` when `inclusive`.
    /// Every name in the range is longer than `position`.
    fn boundary(lo: usize, hi: usize, position: usize, unit: u16, inclusive: bool) usize {
        var low = lo;
        var high = hi;
        while (low < high) {
            const middle = low + (high - low) / 2;
            const value: u16 = table[middle].name[position];
            if (value < unit or (inclusive and value == unit)) low = middle + 1 else high = middle;
        }
        return low;
    }
};

/// Returns the entry named exactly `name`, the text after `&`, or null.
pub fn lookup(name: []const u16) ?*const Entity {
    var matcher: Matcher = .{};
    for (name) |unit| {
        if (!matcher.feed(unit)) return null;
    }
    const best = matcher.best orelse return null;
    return if (table[best].name.len == name.len) &table[best] else null;
}
