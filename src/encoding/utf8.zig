//! The handler of the UTF-8 decoder, Encoding Standard §8.1.1.
//!
//! The handler takes one byte or end-of-queue at a time and keeps its state between calls, so input may arrive in
//! any number of chunks. It never allocates. Both the streaming `Decoder` of this module's root and the engine's
//! one-shot UTF-8 conversions run this handler, so the engine has a single UTF-8 decoder.

const std = @import("std");

pub const Handler = struct {
    code_point: u21 = 0,
    bytes_seen: u2 = 0,
    bytes_needed: u2 = 0,
    lower_boundary: u8 = 0x80,
    upper_boundary: u8 = 0xBF,

    /// The handler's result for one byte.
    pub const Step = union(enum) {
        /// "continue": the byte is consumed, and no code point is complete yet.
        pending,
        /// The byte completes this scalar value.
        scalar: u21,
        /// "error", with the byte consumed.
        failure,
        /// "error" after the handler restored the byte: the caller must give the same byte to the handler again.
        /// The handler is then in its initial state, so the byte never restores twice.
        failure_restore,
    };

    pub fn byte(h: *Handler, b: u8) Step {
        if (h.bytes_needed == 0) {
            switch (b) {
                0x00...0x7F => return .{ .scalar = b },
                0xC2...0xDF => {
                    h.bytes_needed = 1;
                    h.code_point = b & 0x1F;
                },
                0xE0...0xEF => {
                    if (b == 0xE0) h.lower_boundary = 0xA0;
                    if (b == 0xED) h.upper_boundary = 0x9F;
                    h.bytes_needed = 2;
                    h.code_point = b & 0xF;
                },
                0xF0...0xF4 => {
                    if (b == 0xF0) h.lower_boundary = 0x90;
                    if (b == 0xF4) h.upper_boundary = 0x8F;
                    h.bytes_needed = 3;
                    h.code_point = b & 0x7;
                },
                else => return .failure,
            }
            return .pending;
        }
        if (b < h.lower_boundary or b > h.upper_boundary) {
            h.* = .{};
            return .failure_restore;
        }
        h.lower_boundary = 0x80;
        h.upper_boundary = 0xBF;
        h.code_point = (h.code_point << 6) | (b & 0x3F);
        h.bytes_seen += 1;
        if (h.bytes_seen != h.bytes_needed) return .pending;
        std.debug.assert(h.code_point <= 0x10FFFF);
        const code_point = h.code_point;
        h.* = .{};
        return .{ .scalar = code_point };
    }

    /// Processes end-of-queue. Returns true for "error" and false for "finished".
    /// The standard sets only "UTF-8 bytes needed" to 0 here; this resets every field, which no later step can observe.
    pub fn end(h: *Handler) bool {
        const pending = h.bytes_needed != 0;
        h.* = .{};
        return pending;
    }
};

/// Runs the handler over a complete byte sequence, one scalar value or error at a time, without allocating.
/// When `next` returns, the handler holds no pending byte, so `index` is the offset where the next item starts.
pub const Scalars = struct {
    bytes: []const u8,
    index: usize = 0,
    handler: Handler = .{},

    pub const Item = union(enum) {
        scalar: u21,
        failure,
    };

    /// Returns the next scalar value or error, or null after end-of-queue.
    pub fn next(s: *Scalars) ?Item {
        while (s.index < s.bytes.len) {
            switch (s.handler.byte(s.bytes[s.index])) {
                .pending => s.index += 1,
                .scalar => |scalar| {
                    s.index += 1;
                    return .{ .scalar = scalar };
                },
                .failure => {
                    s.index += 1;
                    return .failure;
                },
                // The byte stays unread, so the next call gives it to the handler again.
                .failure_restore => return .failure,
            }
        }
        return if (s.handler.end()) .failure else null;
    }
};
