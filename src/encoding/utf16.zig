//! The handler of the shared UTF-16 decoder, Encoding Standard §14.2.1, for UTF-16BE (§14.3.1) and UTF-16LE (§14.4.1).
//!
//! The handler takes one byte or end-of-queue at a time and keeps its state between calls. It never allocates.

pub const Handler = struct {
    leading_byte: ?u8 = null,
    leading_surrogate: ?u16 = null,
    big_endian: bool,

    /// The handler's result for one byte.
    pub const Step = union(enum) {
        /// "continue": the byte is consumed, and no code point is complete yet.
        pending,
        /// The byte completes this scalar value.
        scalar: u21,
        /// "error", with the byte consumed.
        failure,
        /// "error" for a leading surrogate that this code unit does not follow, and then this scalar value,
        /// which the restored code unit gives when it is read again.
        failure_then_scalar: u16,
    };

    pub fn byte(h: *Handler, b: u8) Step {
        const lead = h.leading_byte orelse {
            h.leading_byte = b;
            return .pending;
        };
        const code_unit: u16 = if (h.big_endian) (@as(u16, lead) << 8) + b else (@as(u16, b) << 8) + lead;
        h.leading_byte = null;
        if (h.leading_surrogate) |leading| {
            h.leading_surrogate = null;
            if (isTrailing(code_unit)) {
                return .{ .scalar = 0x10000 + ((@as(u21, leading) - 0xD800) << 10) + (code_unit - 0xDC00) };
            }
            // The standard restores the code unit's two bytes in input order and returns an error.
            // Reading them again sets the leading byte and then forms the same code unit with no leading surrogate,
            // and that code unit is not a trailing surrogate, so the handler takes those steps here.
            if (isLeading(code_unit)) {
                h.leading_surrogate = code_unit;
                return .failure;
            }
            return .{ .failure_then_scalar = code_unit };
        }
        if (isLeading(code_unit)) {
            h.leading_surrogate = code_unit;
            return .pending;
        }
        if (isTrailing(code_unit)) return .failure;
        return .{ .scalar = code_unit };
    }

    /// Processes end-of-queue and returns the number of errors, at most 1.
    pub fn end(h: *Handler) u2 {
        const pending = h.leading_byte != null or h.leading_surrogate != null;
        h.leading_byte = null;
        h.leading_surrogate = null;
        return @intFromBool(pending);
    }
};

fn isLeading(code_unit: u16) bool {
    return code_unit >= 0xD800 and code_unit <= 0xDBFF;
}

fn isTrailing(code_unit: u16) bool {
    return code_unit >= 0xDC00 and code_unit <= 0xDFFF;
}
