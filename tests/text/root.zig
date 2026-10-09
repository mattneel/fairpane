//! FP-0013 and FP-0108 text and font tests. `build.zig` roots a test artifact here that imports the library module as `fairpane`.

test {
    _ = @import("seed_test.zig");
    _ = @import("fixture_test.zig");
    _ = @import("synthetic_test.zig");
    _ = @import("malformed_test.zig");
    _ = @import("bounds_test.zig");
    _ = @import("grapheme_seed_test.zig");
}
