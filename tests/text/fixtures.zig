//! The embedded FP-0013 font fixtures, their expectation files, and the qualification seeds.

const std = @import("std");

pub const Font = struct {
    /// The fixture directory name under `tests/text/fonts/`.
    dir: []const u8,
    file: []const u8,
    bytes: []const u8,
    expectation: []const u8,
};

pub const fonts = [_]Font{
    .{
        .dir = "noto-sans",
        .file = "NotoSans-Regular.ttf",
        .bytes = @embedFile("fonts/noto-sans/NotoSans-Regular.ttf"),
        .expectation = @embedFile("fonts/noto-sans/NotoSans-Regular.expect.json"),
    },
    .{
        .dir = "noto-sans-arabic",
        .file = "NotoSansArabic-Regular.ttf",
        .bytes = @embedFile("fonts/noto-sans-arabic/NotoSansArabic-Regular.ttf"),
        .expectation = @embedFile("fonts/noto-sans-arabic/NotoSansArabic-Regular.expect.json"),
    },
    .{
        .dir = "noto-sans-devanagari",
        .file = "NotoSansDevanagari-Regular.ttf",
        .bytes = @embedFile("fonts/noto-sans-devanagari/NotoSansDevanagari-Regular.ttf"),
        .expectation = @embedFile("fonts/noto-sans-devanagari/NotoSansDevanagari-Regular.expect.json"),
    },
    .{
        .dir = "noto-sans-cjk-jp-subset",
        .file = "cjk-subset.otf",
        .bytes = @embedFile("fonts/noto-sans-cjk-jp-subset/cjk-subset.otf"),
        .expectation = @embedFile("fonts/noto-sans-cjk-jp-subset/cjk-subset.expect.json"),
    },
};

pub fn font(dir: []const u8) ?Font {
    for (fonts) |f| if (std.mem.eql(u8, f.dir, dir)) return f;
    return null;
}

pub const Seed = struct { id: []const u8, json: []const u8 };

pub const seeds = [_]Seed{
    .{ .id = "latin-baseline", .json = @embedFile("seeds/latin-baseline.json") },
    .{ .id = "arabic-greeting", .json = @embedFile("seeds/arabic-greeting.json") },
    .{ .id = "devanagari-greeting", .json = @embedFile("seeds/devanagari-greeting.json") },
    .{ .id = "cjk-greeting", .json = @embedFile("seeds/cjk-greeting.json") },
    .{ .id = "mixed-direction", .json = @embedFile("seeds/mixed-direction.json") },
    .{ .id = "uncovered-emoji", .json = @embedFile("seeds/uncovered-emoji.json") },
};
